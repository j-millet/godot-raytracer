#[compute]
#version 450

//CONSTANTS

#define BVH_STACK_SIZE 32
#define POS_INF 1.0/0.0
#define NEG_INF -1.0/0.0

//STRUCTS


struct Triangle{
    vec4 v0;
    vec4 e1;
    vec4 e2;
    vec4 n0;
    vec4 n1;
    vec4 n2;
};

struct Material{
    vec4 diffusionColor;
    vec4 emissionColor;
    float emissionIntensity;
    float roughness;
};

struct BVHBBox{
    vec4 aabbStart;
    vec4 aabbEnd;
    int verticesStartLocal;
    int verticesEndLocal;
    int childLeftIndex;
    int childRightIndex;
};

struct Object{
    vec4 position;
    vec4 rotation;
    vec4 scale;
    //Bounding box
    int bvhRootIndex;
    //tris
    int triangleIndicesStart;
    int triangleIndicesEnd;

    //ease the load of rendering spheres, can't stretch them then though
    int isSphere;
    Material material;
};

struct Sphere{
    vec3 position;
    float radius;
};

struct Ray{
    vec3 origin;
    vec3 direction;
    vec3 inverseDirection;
};


struct Hit{
    bool didHit;
    float dist;
    vec3 point;
    vec3 normal;
    int boxTests;
};

struct ObjectHit{
    Hit hit;
    int objectIndex;
};

// DATA

layout(set = 0, binding = 0, rgba32f) uniform image2D image;

layout(set = 0, binding = 1, std430) readonly buffer CameraBuffer {
    vec4 cameraPosition;
    vec4 topLeft;
    vec4 topRight;
    vec4 bottomLeft;
    vec4 bottomRight;
    float elapsed_frames;
    float elapsed_frames_no_movement;
}
camera;

layout(set = 0, binding = 2, std430) readonly buffer ObjectBuffer {
    Object list[];
}
objects;

layout(set = 1, binding = 0, std430) readonly buffer ConstantsBuffer {
    int max_ray_bounces;
    int box_test_threshold;
}
constants;

layout(set = 1, binding = 1, std430) readonly buffer TriangleBuffer {
    Triangle triangles[];
}
triangles;


layout(set = 1, binding = 2, std430) readonly buffer BVHBBoxesBuffer {
    BVHBBox bboxes[];
}
bvh;

layout(local_size_x = 32, local_size_y = 32, local_size_z = 1) in;

//CODE

float rand(inout uint state){
    state = state * 747796405 + 2891336453;
    uint result = ((state >> ((state >> 28)+ 4)) ^ state) * 277803737;
    result = (result >> 22) ^ result;
    return result / 4294967295.0;
}

float pi = 3.1415926535;

float randn(inout uint state){
    float u1 = (rand(state) + 1e-7);
    float u2 = rand(state);
    return sqrt(-2*log(u1))*cos(2*pi*u2);
}

vec3 vec4tovec3(vec4 v4){
    return vec3(v4.x,v4.y,v4.z);
}

vec4 vec3tovec4(vec3 v3){
    return vec4(v3.x,v3.y,v3.z,0);
}

vec3 randVectorInHemisphere(vec3 normal, inout uint seed){
    vec3 rv = normalize(vec3(
        randn(seed),
        randn(seed),
        randn(seed)
    ));
    return rv * -dot(rv,normal);
}

vec3 rotateVec(vec3 vec, vec4 quatRotation){
    vec3 u = vec4tovec3(quatRotation);
    return vec + 2 * cross(u, cross(u, vec) + quatRotation.w * vec);
}

Triangle getTriangle(int index){
    return triangles.triangles[index];
}

Ray rayInObjectLocal(Ray ray, Object object){
    vec4 rotation = normalize(object.rotation);
    vec4 invRot = vec4(-rotation.xyz, rotation.w);
    vec3 localOrigin = rotateVec(ray.origin - vec4tovec3(object.position), invRot) / object.scale.xyz;
    vec3 localDirection = rotateVec(ray.direction, invRot) / object.scale.xyz;


    return Ray(
        localOrigin,
        localDirection,
        1/localDirection
    );
}

vec3 objectPointToWorld(vec3 point, Object object){
    vec4 rotation = normalize(object.rotation);
    return rotateVec(point * object.scale.xyz, rotation) + vec4tovec3(object.position);
}

vec3 objectNormalToWorld(vec3 normal, Object object){
    vec4 rotation = normalize(object.rotation);
    return normalize(rotateVec(normal / object.scale.xyz, rotation));
}


Hit noHit(){
    return Hit(false,POS_INF,vec3(0,0,0),vec3(0,0,0),0);
}

Hit rayIntersectsSphere(
    Ray r,
    Sphere s
){
    vec3 c_prime = r.origin - s.position;
    float b = 2*dot(c_prime,r.direction);
    float c = dot(c_prime,c_prime) - pow(s.radius,2);

    float delta = pow(b,2) - 4*c;
    
    float t = (delta == 0)? -0.5*b:(-1*b - sqrt(delta))/2.0;

    bool correctDelta = delta >= 0;
    bool correctDistance = t > 0;

    vec3 point = r.origin + t*r.direction;
    vec3 normal = normalize(point - s.position);
    
    return Hit(correctDelta && correctDistance,t,point,normal,0); 
}


Hit rayIntersects(
    Ray r,
    Triangle tri,
    float epsilon
){
    vec3 normalA = vec4tovec3(tri.n0);
    vec3 normalB = vec4tovec3(tri.n1);
    vec3 normalC = vec4tovec3(tri.n2);
    
    vec3 normal = normalize((normalA + normalB + normalC) * 0.333333333);

    Hit result = noHit();

    if (dot(normal,r.direction) > 0) return result;


    vec3 triA = vec4tovec3(tri.v0);
    vec3 edge1 = vec4tovec3(tri.e1);
    vec3 edge2 = vec4tovec3(tri.e2);

    vec3 cross_e2 = cross(r.direction,edge2);
    float det = dot(edge1,cross_e2);

    if (abs(det) < epsilon) return result;
    
    float inv_det = 1.0/det;
    vec3 s = r.origin - triA;
    float u = inv_det * dot(s,cross_e2);

    if (u < -epsilon || u - 1 > epsilon) return result;

    vec3 s_cross_e1 = cross(s,edge1);
    float v = inv_det * dot(r.direction, s_cross_e1);

    if (v < -epsilon || u + v - 1 > epsilon) return result;

    float t = inv_det * dot(edge2, s_cross_e1);

    vec3 point = r.origin + t*r.direction;

    bool didHit = t > epsilon;

    result.didHit = didHit;
    result.dist = didHit? t: POS_INF;
    result.point = point;
    result.normal = normal;
    return result;
}


float rayInsideBBoxDist(Ray r, BVHBBox bbox, Object obj){

    vec3 aabbStart = vec4tovec3(bbox.aabbStart);
    vec3 aabbEnd = vec4tovec3(bbox.aabbEnd);
    
    vec3 tMin = (aabbStart - r.origin) * r.inverseDirection;
    vec3 tMax = (aabbEnd - r.origin) * r.inverseDirection;

    vec3 t1 = min(tMin,tMax);
    vec3 t2 = max(tMin,tMax);

    float dstFar = min(min(t2.x,t2.y),t2.z);
    float dstNear = max(max(t1.x,t1.y),t1.z);

    return (dstFar >= dstNear && dstFar > 0)? dstNear:POS_INF;

}

Hit rayIntersectsObject(Ray r, Object obj){
    int bvhStack[BVH_STACK_SIZE];
    int stackPtr = 0;

    bvhStack[stackPtr++] = 0;


    Hit objHit = noHit();
    int tests = 0;
    while (stackPtr > 0 && stackPtr < BVH_STACK_SIZE){
        int bboxIndex = bvhStack[--stackPtr];
        BVHBBox bbox = bvh.bboxes[obj.bvhRootIndex + bboxIndex];
        tests++;
        float bbox_dist = rayInsideBBoxDist(r, bbox, obj);
        if (bbox_dist >= objHit.dist){
            continue;
        }
        if (bbox.childLeftIndex == 0 && bbox.childRightIndex == 0){
            int startIdx = bbox.verticesStartLocal + obj.triangleIndicesStart;
            int endIdx = bbox.verticesEndLocal + obj.triangleIndicesStart;
            

            for(int j = startIdx; j < endIdx && j < obj.triangleIndicesEnd; j++){
                Hit h = rayIntersects(r, getTriangle(j), 0.00001);
                bool closer = h.didHit && (h.dist < objHit.dist);
                objHit.boxTests++;
                objHit = closer ? h : objHit;
            }
        }
        else{
            BVHBBox childLeft = bvh.bboxes[obj.bvhRootIndex + bbox.childLeftIndex];
            BVHBBox childRight = bvh.bboxes[obj.bvhRootIndex + bbox.childRightIndex];
            float childLeftDist = rayInsideBBoxDist(r, childLeft, obj);
            float childRightDist = rayInsideBBoxDist(r, childRight, obj);
            if (childLeftDist > childRightDist){
                if (childRightDist < objHit.dist) bvhStack[stackPtr++] = bbox.childRightIndex;
                if (childLeftDist < objHit.dist) bvhStack[stackPtr++] = bbox.childLeftIndex;
            }
            else{
                if (childLeftDist < objHit.dist) bvhStack[stackPtr++] = bbox.childLeftIndex;
                if (childRightDist < objHit.dist) bvhStack[stackPtr++] = bbox.childRightIndex;
            }
        }
    }
    return objHit;
}

ObjectHit trace(Ray r){
    Hit minHit = Hit(false,10000000.0,vec3(0,0,0),vec3(0,0,0),0);
    int minObjIndex = -1;

    for (int i = 0; i < objects.list.length(); i++){
        Object obj = objects.list[i];

        Hit objHit = Hit(false, 1e7, vec3(0), vec3(0),0);

        // if (obj.isSphere == 1){
        //     objHit = rayIntersectsSphere(
        //         r,
        //         Sphere(
        //             vec4tovec3(obj.position),
        //             obj.scale.x/2.0
        //         )
        //     );
        // }
        // else{
            Ray localRay = rayInObjectLocal(r, obj);
            objHit = rayIntersectsObject(localRay, obj);

            if (objHit.didHit){
                objHit.point = objectPointToWorld(objHit.point, obj);
                objHit.normal = objectNormalToWorld(objHit.normal, obj);
                objHit.dist = length(objHit.point - r.origin);
            }
        // }

        bool closer = objHit.didHit && (objHit.dist < minHit.dist);
        minHit = closer ? objHit : minHit;
        minObjIndex = closer ? i : minObjIndex;
    }

    
    return ObjectHit(
        minHit,minObjIndex
    );
}

Ray makeRay(vec3 origin, vec3 direction){
    return Ray(
        origin,
        direction,
        1/direction
    );
}


void main() {
    ivec2 coords = ivec2(gl_GlobalInvocationID.xy);

    uint seed = uint(camera.elapsed_frames) * coords.x * coords.y;

    float sizex = gl_NumWorkGroups.x*gl_WorkGroupSize.x;
    float sizey = gl_NumWorkGroups.y*gl_WorkGroupSize.y;


    vec2 uv = vec2(
        float(coords.x) / sizex,
        float(coords.y)/ sizey
    );
	float xshift = rand(seed)/sizex;
	vec3 pixel_point = normalize(vec4tovec3(mix(
        mix(camera.topLeft,camera.topRight, uv.x+xshift),
        mix(camera.bottomLeft,camera.bottomRight,uv.x+xshift),
        uv.y + rand(seed)/sizey
    )));

    vec4 value = vec4(0,0,0,1.0);
    vec4 rayColor = vec4(1,1,1,1);


    Ray r = makeRay(vec4tovec3(camera.cameraPosition),pixel_point);
    for (int i = 0; i < constants.max_ray_bounces;i++){
        ObjectHit traceInfo = trace(r);
        if (!traceInfo.hit.didHit){
            break;
        }
        Object hitObj = objects.list[traceInfo.objectIndex];
        value += (hitObj.material.emissionColor) * hitObj.material.emissionIntensity * rayColor;
        rayColor *= hitObj.material.diffusionColor;
        r = makeRay(
            traceInfo.hit.point,
            normalize(
                mix(
                    reflect(r.direction,traceInfo.hit.normal),
                    traceInfo.hit.normal + randVectorInHemisphere(traceInfo.hit.normal, seed),
                    hitObj.material.roughness
                )));
    }
    value.w = 1.0;
    
    vec4 total_value = int(camera.elapsed_frames_no_movement) == 1? vec4(0,0,0,0):imageLoad(image,coords);
    total_value = ((total_value * (camera.elapsed_frames_no_movement-1)) + value)/(camera.elapsed_frames_no_movement);

    imageStore(image,coords,total_value);
}
