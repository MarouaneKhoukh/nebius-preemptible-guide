// Add two vectors on the GPU, then verify every result on the CPU.
#include <cuda_runtime.h>

#include <cmath>
#include <cstdlib>
#include <iomanip>
#include <iostream>
#include <vector>

static void check(cudaError_t status, const char* operation) {
    if (status != cudaSuccess) {
        std::cerr << operation << ": " << cudaGetErrorString(status) << '\n';
        std::exit(EXIT_FAILURE);
    }
}

__global__ void add(const float* a, const float* b, float* result, int count) {
    const int index = blockIdx.x * blockDim.x + threadIdx.x;
    if (index < count) result[index] = a[index] + b[index];
}

int main() {
    constexpr int count = 4096;
    constexpr size_t bytes = count * sizeof(float);
    int devices = 0;
    check(cudaGetDeviceCount(&devices), "Find GPU");
    if (devices == 0) {
        std::cerr << "No CUDA GPU is available.\n";
        return EXIT_FAILURE;
    }
    check(cudaSetDevice(0), "Select GPU");
    cudaDeviceProp device{};
    check(cudaGetDeviceProperties(&device, 0), "Read GPU name");

    std::vector<float> a(count), b(count), result(count);
    for (int i = 0; i < count; ++i) {
        a[i] = i * 0.25f;
        b[i] = i * 0.5f;
    }
    float *gpu_a = nullptr, *gpu_b = nullptr, *gpu_result = nullptr;
    check(cudaMalloc(&gpu_a, bytes), "Allocate first vector");
    check(cudaMalloc(&gpu_b, bytes), "Allocate second vector");
    check(cudaMalloc(&gpu_result, bytes), "Allocate result");
    check(cudaMemcpy(gpu_a, a.data(), bytes, cudaMemcpyHostToDevice), "Copy first vector");
    check(cudaMemcpy(gpu_b, b.data(), bytes, cudaMemcpyHostToDevice), "Copy second vector");
    add<<<(count + 255) / 256, 256>>>(gpu_a, gpu_b, gpu_result, count);
    check(cudaGetLastError(), "Launch vector addition");
    check(cudaDeviceSynchronize(), "Finish vector addition");
    check(cudaMemcpy(result.data(), gpu_result, bytes, cudaMemcpyDeviceToHost), "Read result");
    check(cudaFree(gpu_result), "Free result");
    check(cudaFree(gpu_b), "Free second vector");
    check(cudaFree(gpu_a), "Free first vector");

    for (int i = 0; i < count; ++i) {
        if (!std::isfinite(result[i]) || std::fabs(result[i] - (a[i] + b[i])) > 1e-5f) {
            std::cerr << "Incorrect GPU result at element " << i << '\n';
            return EXIT_FAILURE;
        }
    }
    std::cout << "{\"device\":" << std::quoted(device.name)
              << ",\"elements\":" << count << ",\"pass\":true}\n";
    return EXIT_SUCCESS;
}
