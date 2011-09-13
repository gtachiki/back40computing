/******************************************************************************
 * 
 * Copyright 2010 Duane Merrill
 * 
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 * 
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License. 
 * 
 * For more information, see our Google Code project site: 
 * http://code.google.com/p/back40computing/
 * 
 * Thanks!
 * 
 ******************************************************************************/

/******************************************************************************
 * Common device intrinsics (potentially specialized by architecture)
 ******************************************************************************/

#pragma once

#include <b40c/util/cuda_properties.cuh>
#include <b40c/util/reduction/warp_reduce.cuh>

namespace b40c {
namespace util {


/**
 * BFE (bitfield extract).   Extracts a bit field from source and places the
 * zero or sign-extended result in extract
 */
__device__ __forceinline__ static void BFE(int &bits, int source, int bit_start, int num_bits)
{
#if __CUDA_ARCH__ >= 200
	asm("bfe.u32 %0, %1, %2, %3;" : "=r"(bits) : "r"(source), "r"(bit_start), "r"(num_bits));
#else
	const int MASK = (1 << num_bits) - 1;
	bits = (source >> bit_start) & MASK;
#endif
}

__device__ __forceinline__ static int BFE(int source, int bit_start, int num_bits)
{
	int bits;
#if __CUDA_ARCH__ >= 200
	asm("bfe.u32 %0, %1, %2, %3;" : "=r"(bits) : "r"(source), "r"(bit_start), "r"(num_bits));
#else
	const int MASK = (1 << num_bits) - 1;
	bits = (source >> bit_start) & MASK;
#endif
	return bits;
}


/**
 * BFI (bitfield insert).  Inserts the first num_bits of y into x starting at bit_start
 */
__device__ __forceinline__ void BFI(int &ret, int x, int y, int bit_start, int num_bits)
{
#if __CUDA_ARCH__ >= 200
	asm("bfi.b32 %0, %1, %2, %3, %4;" :
		"=r"(ret) : "r"(y), "r"(x), "r"(bit_start), "r"(num_bits));
#else
	// TODO
#endif
}


/**
 * SHL_ADD (shift-left then add)
 */
__device__ __forceinline__ void SHL_ADD(int &ret, int x, int shift, int addend)
{
#if __CUDA_ARCH__ >= 200
	asm("vshl.u32.u32.u32.clamp.add %0, %1, %2, %3;" :
		"=r"(ret) : "r"(x), "r"(shift), "r"(addend));
#else
	ret = (x << shift) + addend;
#endif
}


/**
 * PMT (byte permute).  Pick four arbitrary bytes from two 32-bit registers, and
 * reassemble them into a 32-bit destination register
 */
__device__ __forceinline__ void PRMT(int &ret, int a, int b, int index)
{
	asm("prmt.b32 %0, %1, %2, %3;" : "=r"(ret) : "r"(a), "r"(b), "r"(index));
}
__device__ __forceinline__ int PRMT(int a, int b, int index)
{
	int ret;
	asm("prmt.b32 %0, %1, %2, %3;" : "=r"(ret) : "r"(a), "r"(b), "r"(index));
	return ret;
}


/**
 * Expands packed nibbles into packed bytes
 */
__device__ __forceinline__ static void NibblesToBytes(
	int int_bytes[2], int int_nibbles)
{
	int nib_shifted = int_nibbles >> 4;

	PRMT(int_bytes[0], int_nibbles, nib_shifted, 0x5140);
	int_bytes[0] &= 0x0f0f0f0f;

	PRMT(int_bytes[1], int_nibbles, nib_shifted, 0x7362);
	int_bytes[1] &= 0x0f0f0f0f;
}


/**
 * Expands packed nibbles into packed bytes
 */
__device__ __forceinline__ static void BytesToHalves(
	int int_halves[2], int int_bytes)
{
	PRMT(int_halves[0], int_bytes, 0, 0x4140);
	PRMT(int_halves[1], int_bytes, 0, 0x4342);
}








/**
 * Terminates the calling thread
 */
__device__ __forceinline__ void ThreadExit() {
	asm("exit;");
}	


/**
 * Returns the warp lane ID of the calling thread
 */
__device__ __forceinline__ unsigned int LaneId()
{
	unsigned int ret;
	asm("mov.u32 %0, %laneid;" : "=r"(ret) );
	return ret;
}


/**
 * The best way to multiply integers (24 effective bits or less)
 */
__device__ __forceinline__ unsigned int FastMul(unsigned int a, unsigned int b)
{
#if __CUDA_ARCH__ >= 200
	return a * b;
#else
	return __umul24(a, b);
#endif
}


/**
 * The best way to multiply integers (24 effective bits or less)
 */
__device__ __forceinline__ int FastMul(int a, int b)
{
#if __CUDA_ARCH__ >= 200
	return a * b;
#else
	return __mul24(a, b);
#endif	
}


/**
 * The best way to tally a warp-vote
 */
template <int LOG_ACTIVE_WARPS, int LOG_ACTIVE_THREADS>
__device__ __forceinline__ int TallyWarpVote(int predicate)
{
#if __CUDA_ARCH__ >= 200
	return __popc(__ballot(predicate));
#else
	const int ACTIVE_WARPS = 1 << LOG_ACTIVE_WARPS;
	const int ACTIVE_THREADS = 1 << LOG_ACTIVE_THREADS;

	__shared__ volatile int storage[ACTIVE_WARPS + 1][ACTIVE_THREADS];

	int tid = threadIdx.x & (B40C_WARP_THREADS(__B40C_CUDA_ARCH__) - 1);
	int wid = threadIdx.x >> B40C_LOG_WARP_THREADS(__B40C_CUDA_ARCH__);

	return reduction::WarpReduce<LOG_ACTIVE_THREADS>::Invoke(predicate, storage[wid], tid);
#endif
}


/**
 * The best way to tally a warp-vote in the first warp
 */
template <int LOG_ACTIVE_THREADS>
__device__ __forceinline__ int TallyWarpVote(
	int predicate,
	volatile int storage[2][1 << LOG_ACTIVE_THREADS])
{
#if __CUDA_ARCH__ >= 200
	return __popc(__ballot(predicate));
#else
	return reduction::WarpReduce<LOG_ACTIVE_THREADS>::Invoke(
		predicate, 
		storage);
#endif
}


/**
 * The best way to warp-vote-all
 */
template <int LOG_ACTIVE_WARPS, int LOG_ACTIVE_THREADS>
__device__ __forceinline__ int WarpVoteAll(int predicate)
{
#if __CUDA_ARCH__ >= 120
	return __all(predicate);
#else 
	const int ACTIVE_THREADS = 1 << LOG_ACTIVE_THREADS;
	return (TallyWarpVote<LOG_ACTIVE_WARPS, LOG_ACTIVE_THREADS>(predicate) == ACTIVE_THREADS);
#endif
}


/**
 * The best way to warp-vote-all in the first warp
 */
template <int LOG_ACTIVE_THREADS>
__device__ __forceinline__ int WarpVoteAll(int predicate)
{
#if __CUDA_ARCH__ >= 120
	return __all(predicate);
#else
	const int ACTIVE_THREADS = 1 << LOG_ACTIVE_THREADS;
	__shared__ volatile int storage[2][ACTIVE_THREADS];

	return (TallyWarpVote<LOG_ACTIVE_THREADS>(predicate, storage) == ACTIVE_THREADS);
#endif
}

/**
 * The best way to warp-vote-any
 */
template <int LOG_ACTIVE_WARPS, int LOG_ACTIVE_THREADS>
__device__ __forceinline__ int WarpVoteAny(int predicate)
{
#if __CUDA_ARCH__ >= 120
	return __any(predicate);
#else
	return TallyWarpVote<LOG_ACTIVE_WARPS, LOG_ACTIVE_THREADS>(predicate);
#endif
}


/**
 * The best way to warp-vote-any in the first warp
 */
template <int LOG_ACTIVE_THREADS>
__device__ __forceinline__ int WarpVoteAny(int predicate)
{
#if __CUDA_ARCH__ >= 120
	return __any(predicate);
#else
	const int ACTIVE_THREADS = 1 << LOG_ACTIVE_THREADS;
	__shared__ volatile int storage[2][ACTIVE_THREADS];

	return TallyWarpVote<LOG_ACTIVE_THREADS>(predicate, storage);
#endif
}


/**
 * Wrapper for performing atomic operations on integers of type size_t 
 */
template <typename T, int SizeT = sizeof(T)>
struct AtomicInt;

template <typename T>
struct AtomicInt<T, 4>
{
	static __device__ __forceinline__ T Add(T* ptr, T val)
	{
		return atomicAdd((unsigned int *) ptr, (unsigned int) val);
	}
};

template <typename T>
struct AtomicInt<T, 8>
{
	static __device__ __forceinline__ T Add(T* ptr, T val)
	{
		return atomicAdd((unsigned long long int *) ptr, (unsigned long long int) val);
	}
};


} // namespace util
} // namespace b40c

