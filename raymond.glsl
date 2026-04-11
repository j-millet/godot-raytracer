#[compute]
#version 450

//CONSTANTS

#define BVH_STACK_SIZE 32

//STRUCTS


struct Triangle{
    vec3 pointA;
    vec3 pointB;
    vec3 pointC;
    vec3 normalA;
    vec3 normalB;
    vec3 normalC;
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
};


struct Hit{
    bool didHit;
    float dist;
    vec3 point;
    vec3 normal;
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
}
camera;

layout(set = 0, binding = 2, std430) readonly buffer ObjectBuffer {
    Object list[];
}
objects;

layout(set = 1, binding = 0, std430) readonly buffer ConstantsBuffer {
    int max_ray_bounces;
}
constants;

layout(set = 1, binding = 1, std430) readonly buffer VertexBuffer {
    vec4 coords[];
}
vertices;

layout(set = 1, binding = 2, std430) readonly buffer VertexIdxBuffer {
    int indices[];
}
vertexIndices;


layout(set = 1, binding = 3, std430) readonly buffer VertexNormalBuffer {
    vec4 vecs[];
}
vertexNormals;

layout(set = 1, binding = 4, std430) readonly buffer BVHBBoxesBuffer {
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
    float u1 = rand(state);
    float u2 = rand(state);
    return sqrt(-2*log(u1))*cos(2*pi*u2);
}

vec3 vec4tovec3(vec4 v4){
    return vec3(v4.x,v4.y,v4.z);
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

Triangle getTriangle(int index, Object owner){
    int i1 = vertexIndices.indices[index];
    int i2 = vertexIndices.indices[index + 1];
    int i3 = vertexIndices.indices[index + 2];
    return Triangle(
        rotateVec(vec4tovec3(vertices.coords[i1] * owner.scale),owner.rotation)  + vec4tovec3(owner.position),
        rotateVec(vec4tovec3(vertices.coords[i2] * owner.scale),owner.rotation)  + vec4tovec3(owner.position),
        rotateVec(vec4tovec3(vertices.coords[i3] * owner.scale),owner.rotation)  + vec4tovec3(owner.position),
        rotateVec(vec4tovec3(vertexNormals.vecs[i1]),owner.rotation),
        rotateVec(vec4tovec3(vertexNormals.vecs[i2]),owner.rotation),
        rotateVec(vec4tovec3(vertexNormals.vecs[i3]),owner.rotation)
    );
}


Hit noHit(){
    return Hit(false,0,vec3(0,0,0),vec3(0,0,0));
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
    
    return Hit(correctDelta && correctDistance,t,point,normal); 
}


Hit rayIntersects(
    Ray r,
    Triangle tri,
    float epsilon
){
    vec3 normalA = tri.normalA;
    vec3 normalB = tri.normalB;
    vec3 normalC = tri.normalC;
    
    vec3 normal = normalize((normalA + normalB + normalC) * 0.333333333);

    Hit result = noHit();


    vec3 triA = tri.pointA;
    vec3 triB = tri.pointB;
    vec3 triC = tri.pointC;

    vec3 edge1 = triB - triA;
    vec3 edge2 = triC - triA;

    vec3 cross_e2 = cross(r.direction,edge2);
    float det = dot(edge1,cross_e2);
    
    float inv_det = 1.0/det;
    vec3 s = r.origin - triA;
    float u = inv_det * dot(s,cross_e2);


    vec3 s_cross_e1 = cross(s,edge1);
    float v = inv_det * dot(r.direction, s_cross_e1);

    float t = inv_det * dot(edge2, s_cross_e1);

    vec3 point = r.origin + t*r.direction;

    bool frontFace = dot(r.direction, normal) < 0.0;
    bool validDet = abs(det) > epsilon;
    bool validU = (u >= -epsilon) && (u <= 1.0 + epsilon);
    bool validV = (v >= -epsilon) && (u + v <= 1.0 + epsilon);
    bool validT = t > epsilon;

    bool didHit = frontFace && validDet && validU && validV && validT;

    result.didHit = didHit;
    result.dist = didHit? t: 1e7;
    result.point = point;
    result.normal = normal;
    return result;
}


bool rayInsideBBox(Ray r, BVHBBox bbox){

    vec3 aabbStart = vec4tovec3(bbox.aabbStart);
    vec3 aabbEnd = vec4tovec3(bbox.aabbEnd);
    
    float tmin = -1.0 / 0.0; // -INF
    float tmax = 1.0 / 0.0;  // +INF

    for (int i = 0; i < 3; i++)
    {
        float invD = 1.0 / r.direction[i];
        float t0 = (aabbStart[i] - r.origin[i]) * invD;
        float t1 = (aabbEnd[i] - r.origin[i]) * invD;
        
        float tmp = t0;
        t0 = (invD < 0.0)? t1:t0;
        t1 = (invD < 0.0)? tmp:t1;


        tmin = max(tmin, t0);
        tmax = min(tmax, t1);

        if (tmax + 0.00001 <= tmin)
            return false;
    }

    return true;
}

Hit rayIntersectsObject(Ray r, Object obj){
    int bvhStack[BVH_STACK_SIZE];
    int stackPtr = 0;

    bvhStack[stackPtr++] = 0;

    while (stackPtr > 0 && stackPtr < BVH_STACK_SIZE){
        int bboxIndex = bvhStack[--stackPtr];
        BVHBBox bbox = bvh.bboxes[obj.bvhRootIndex + bboxIndex];
        if (!rayInsideBBox(r,bbox)){
            continue;
        }
        if (bbox.childLeftIndex == 0 && bbox.childRightIndex == 0){
            int startIdx = bbox.verticesStartLocal + obj.triangleIndicesStart;
            int endIdx = bbox.verticesEndLocal + obj.triangleIndicesStart;
            
            Hit objHit = Hit(false, 1e7, vec3(0), vec3(0));

            for(int j = startIdx; j < endIdx && j < obj.triangleIndicesEnd; j+=3){
                Hit h = rayIntersects(r, getTriangle(j, obj), 0.00001);
                bool closer = h.didHit && (h.dist < objHit.dist);
                objHit = closer ? h : objHit;
            }
            return objHit;
        }
        if (bbox.childLeftIndex > 0)
                bvhStack[stackPtr++] = bbox.childLeftIndex;

        if (bbox.childRightIndex > 0)
            bvhStack[stackPtr++] = bbox.childRightIndex;
    }
    return noHit();
}

ObjectHit trace(Ray r){
    Hit minHit = Hit(false,10000000.0,vec3(0,0,0),vec3(0,0,0));
    int minObjIndex = -1;

    for (int i = 0; i < objects.list.length(); i++){
        Object obj = objects.list[i];
        BVHBBox bvhroot = bvh.bboxes[obj.bvhRootIndex];

        if (!rayInsideBBox(r,bvhroot)){
            continue;
        }

        Hit objHit = Hit(false, 1e7, vec3(0), vec3(0));

        if (obj.isSphere == 1){
            objHit = rayIntersectsSphere(
                r,
                Sphere(
                    vec4tovec3(obj.position),
                    obj.scale.x/2.0
                )
            );
        }
        else{
            objHit = rayIntersectsObject(r, obj);
        }

        bool closer = objHit.didHit && (objHit.dist < minHit.dist);
        minHit = closer ? objHit : minHit;
        minObjIndex = closer ? i : minObjIndex;
    }

    
    return ObjectHit(
        minHit,minObjIndex
    );
}


void main() {
    ivec2 coords = ivec2(gl_GlobalInvocationID.xy);
    vec2 uv = vec2(
        float(coords.x)/(gl_NumWorkGroups.x)/gl_WorkGroupSize.x,
        float(coords.y)/(gl_NumWorkGroups.y)/gl_WorkGroupSize.y
    );

	vec3 pixel_point = normalize(vec4tovec3(mix(
        mix(camera.topLeft,camera.topRight, uv.x),
        mix(camera.bottomLeft,camera.bottomRight,uv.x),
        uv.y
    )));

    vec4 value = vec4(0,0,0,1.0);
    vec4 rayColor = vec4(1,1,1,1);

    uint seed = uint(camera.elapsed_frames) * coords.x * coords.y;

    Ray r = Ray(vec4tovec3(camera.cameraPosition),pixel_point);
    for (int i = 0; i < constants.max_ray_bounces;i++){
        ObjectHit traceInfo = trace(r);
        if (!traceInfo.hit.didHit){
            break;
        }
        // float col = -dot(r.direction, traceInfo.hit.normal);
        // value = vec4(
        //     1.0 * col,
        //     1.0 * col,
        //     1.0 * col,
        //     1.0
        // );
        // break;
        Object hitObj = objects.list[traceInfo.objectIndex];
        value += (hitObj.material.emissionColor) * hitObj.material.emissionIntensity * rayColor;
        rayColor *= hitObj.material.diffusionColor;
        r = Ray(
            traceInfo.hit.point,
            normalize(
                mix(
                    reflect(r.direction,traceInfo.hit.normal),
                    traceInfo.hit.normal + randVectorInHemisphere(traceInfo.hit.normal, seed),
                    hitObj.material.roughness
                )));
    }

    //value = vec4(float(constants.max_ray_bounces)/2.0,0,0,0);

    value.w = 1.0;
    
    vec4 total_value = int(camera.elapsed_frames) == 1? vec4(0,0,0,0):imageLoad(image,coords);
    total_value = ((total_value * (camera.elapsed_frames-1)) + value)/(camera.elapsed_frames);

    imageStore(image,coords,total_value);
}