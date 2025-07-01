#include "tensorrt_rtx_ffi.h"
#include <NvInfer.h>
#include <NvOnnxParser.h>
#include <cuda_runtime_api.h>
#include <vector>
#include <memory>
#include <fstream>
#include <cstring>
#include <iostream>

using namespace nvinfer1;

namespace {

class Logger : public ILogger {
public:
    void log(Severity severity, const char* msg) noexcept override {
        if (severity <= Severity::kWARNING) {
            std::cout << msg << std::endl;
        }
    }
} gLogger;

static std::vector<char> readFile(const char* path) {
    std::ifstream file(path, std::ios::binary | std::ios::ate);
    if (!file) return {};
    std::streamsize size = file.tellg();
    file.seekg(0, std::ios::beg);
    std::vector<char> buffer(size);
    file.read(buffer.data(), size);
    return buffer;
}

struct TrtRtxContext {
    std::vector<float> input_buffers[2];
    std::vector<float> host_dets;
    std::vector<float> host_keypoints;
    IRuntime* runtime = nullptr;
    ICudaEngine* engine = nullptr;
    IExecutionContext* context = nullptr;
    void* bindings[3] = {};
    cudaStream_t stream{};
    int det_count = 0;
    size_t input_size = 0;
    size_t dets_size = 0;
    size_t kpts_size = 0;
};

} // namespace

extern "C" {

void* trt_rtx_create(const char* model_path) {
    auto ctx = new TrtRtxContext();
    ctx->input_buffers[0].resize(640 * 640 * 3);
    ctx->input_buffers[1].resize(640 * 640 * 3);
    ctx->input_size = ctx->input_buffers[0].size() * sizeof(float);

    auto builder = createInferBuilder(gLogger);
    auto network = builder->createNetworkV2(0);
    auto parser = nvonnxparser::createParser(*network, gLogger);
    auto onnx_data = readFile(model_path);
    if (onnx_data.empty()) {
        delete ctx;
        parser->destroy();
        network->destroy();
        builder->destroy();
        return nullptr;
    }
    if (!parser->parse(onnx_data.data(), onnx_data.size())) {
        delete ctx;
        parser->destroy();
        network->destroy();
        builder->destroy();
        return nullptr;
    }

    auto config = builder->createBuilderConfig();
    builder->setMaxBatchSize(1);
    ctx->engine = builder->buildEngineWithConfig(*network, *config);
    parser->destroy();
    network->destroy();
    config->destroy();
    builder->destroy();

    if (!ctx->engine) {
        delete ctx;
        return nullptr;
    }

    ctx->runtime = nullptr; // runtime not needed after building
    ctx->context = ctx->engine->createExecutionContext();
    cudaStreamCreate(&ctx->stream);

    int input_idx = ctx->engine->getBindingIndex("input");
    int det_idx = ctx->engine->getBindingIndex("dets");
    int kp_idx = ctx->engine->getBindingIndex("keypoints");

    auto det_dims = ctx->engine->getBindingDimensions(det_idx);
    ctx->det_count = det_dims.d[1];
    ctx->host_dets.resize(ctx->det_count * 5);
    ctx->host_keypoints.resize(ctx->det_count * 17 * 3);
    ctx->dets_size = ctx->host_dets.size() * sizeof(float);
    ctx->kpts_size = ctx->host_keypoints.size() * sizeof(float);

    cudaMalloc(&ctx->bindings[input_idx], ctx->input_size);
    cudaMalloc(&ctx->bindings[det_idx], ctx->dets_size);
    cudaMalloc(&ctx->bindings[kp_idx], ctx->kpts_size);

    return ctx;
}

void trt_rtx_destroy(void* c) {
    auto ctx = static_cast<TrtRtxContext*>(c);
    if (!ctx) return;
    cudaFree(ctx->bindings[0]);
    cudaFree(ctx->bindings[1]);
    cudaFree(ctx->bindings[2]);
    if (ctx->context) ctx->context->destroy();
    if (ctx->engine) ctx->engine->destroy();
    cudaStreamDestroy(ctx->stream);
    delete ctx;
}

float* trt_rtx_input_buffer(void* c, int index) {
    auto ctx = static_cast<TrtRtxContext*>(c);
    return ctx->input_buffers[index].data();
}

size_t trt_rtx_run(void* c, int index, RtxDetection* dets, size_t max_dets) {
    auto ctx = static_cast<TrtRtxContext*>(c);
    const float* host_in = ctx->input_buffers[index].data();
    cudaMemcpyAsync(ctx->bindings[0], host_in, ctx->input_size, cudaMemcpyHostToDevice, ctx->stream);

    ctx->context->executeV2(ctx->bindings);

    cudaMemcpyAsync(ctx->host_dets.data(), ctx->bindings[1], ctx->dets_size, cudaMemcpyDeviceToHost, ctx->stream);
    cudaMemcpyAsync(ctx->host_keypoints.data(), ctx->bindings[2], ctx->kpts_size, cudaMemcpyDeviceToHost, ctx->stream);
    cudaStreamSynchronize(ctx->stream);

    size_t out_idx = 0;
    for (int i = 0; i < ctx->det_count && out_idx < max_dets; ++i) {
        float score = ctx->host_dets[i * 5 + 4];
        if (score < 0.5f)
            continue;
        RtxDetection& out = dets[out_idx];
        float x1 = ctx->host_dets[i * 5];
        float y1 = ctx->host_dets[i * 5 + 1];
        float x2 = ctx->host_dets[i * 5 + 2];
        float y2 = ctx->host_dets[i * 5 + 3];
        out.box[0] = x1;
        out.box[1] = y1;
        out.box[2] = x2 - x1;
        out.box[3] = y2 - y1;
        out.score = score;
        for (int k = 0; k < 17; ++k) {
            out.keypoints[k * 3] = ctx->host_keypoints[i * 17 * 3 + k * 3];
            out.keypoints[k * 3 + 1] = ctx->host_keypoints[i * 17 * 3 + k * 3 + 1];
            out.keypoints[k * 3 + 2] = ctx->host_keypoints[i * 17 * 3 + k * 3 + 2];
        }
        ++out_idx;
    }
    return out_idx;
}

} // extern "C"
