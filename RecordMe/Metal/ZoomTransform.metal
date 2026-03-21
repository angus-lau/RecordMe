#include <metal_stdlib>
using namespace metal;

struct ZoomParams {
    float scale;
    float focalX;
    float focalY;
    uint outputWidth;
    uint outputHeight;
    uint sourceWidth;
    uint sourceHeight;
};

kernel void zoomTransform(
    texture2d<float, access::read> source [[texture(0)]],
    texture2d<float, access::write> dest [[texture(1)]],
    constant ZoomParams &params [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= params.outputWidth || gid.y >= params.outputHeight) return;

    float u = float(gid.x) / float(params.outputWidth);
    float v = float(gid.y) / float(params.outputHeight);

    float srcU = params.focalX + (u - 0.5) / params.scale;
    float srcV = params.focalY + (v - 0.5) / params.scale;

    srcU = clamp(srcU, 0.0, 1.0);
    srcV = clamp(srcV, 0.0, 1.0);

    uint srcX = uint(srcU * float(params.sourceWidth - 1));
    uint srcY = uint(srcV * float(params.sourceHeight - 1));

    float4 color = source.read(uint2(srcX, srcY));
    dest.write(color, gid);
}
