/******************************************************************************
 * 
 * Copyright (c) 2011-2012, Duane Merrill.  All rights reserved.
 * Copyright (c) 2011-2012, NVIDIA CORPORATION.  All rights reserved.
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
 ******************************************************************************/

/******************************************************************************
 * CTA-processing abstraction for reduction kernels
 ******************************************************************************/

#pragma once

#include <iterator>

#include <cub/work_distribution.cuh>

namespace b40 {
namespace reduction {

using namespace cub;


/**
 * Reduction CTA abstraction
 */
template <
	typename KernelPolicy,
	typename InputIterator,
	typename OutputIterator,
	typename ReductionOp,
	typename SizeT>
struct Cta
{
	//---------------------------------------------------------------------
	// Typedefs
	//---------------------------------------------------------------------

	// The value of the type that we're reducing
	typedef typename std::iterator_traits<InputIterator>::value_type T;

	// CTA progress type
	typedef CtaProgress<
		SizeT,
		KernelPolicy::TILE_ELEMENTS,
		KernelPolicy::WORK_STEALING> CtaProgress;

	// Tile reader type

	// CTA reduction type

	// Shared memory layout
	struct SmemStorage
	{
	};

	//---------------------------------------------------------------------
	// Constants
	//---------------------------------------------------------------------



	//---------------------------------------------------------------------
	// Thread fields
	//---------------------------------------------------------------------

	InputIterator		d_in;				// Input iterator
	OutputIterator		d_out;				// Output iterator
	T 					accumulator;		// The value we will accumulate (in each thread)
	ReductionOp			reduction_op;		// Reduction operator
	CtaProgress			cta_progress;		// CTA progress


	//---------------------------------------------------------------------
	// Methods
	//---------------------------------------------------------------------

	/**
	 * Constructor
	 */
	template <typename WorkDistribution>
	__device__ __forceinline__ Cta(
		SmemStorage 					&smem_storage,
		InputIterator 					d_in,
		OutputIterator 					d_out,
		ReductionOp 					reduction_op,
		const WorkDistribution			&work_distribution) :
			// Initializers
			d_in(d_in),
			d_out(d_out),
			reduction_op(reduction_op),
			cta_progress(work_distribution)
	{}


	/**
	 * Process a single, full tile
	 *
	 * Each thread reduces only the strided values it loads.
	 */
	__device__ __forceinline__ void ProcessFullTile(bool first_tile)
	{
	}


	/**
	 * Process a single, partial tile
	 *
	 * Each thread reduces only the strided values it loads.
	 */
	__device__ __forceinline__ void ProcessPartialTile(bool first_tile)
	{
	}


	/**
	 * Guarded collective reduction across all threads, stores final reduction
	 * to output. Used to collectively reduce each thread's aggregate after striding through
	 * the input.
	 *
	 * Only threads with ranks less than num_elements are assumed to have valid
	 * accumulator data.
	 */
	__device__ __forceinline__ void OutputToSpine(int num_elements)
	{
	}


	/**
	 * Process work range of tiles
	 */
	__device__ __forceinline__ void ProcessTiles()
	{
		// Check for at least one full tile of tile_elements
		if (cta_progress.HasTile()) {

			// Process first tile
			ProcessFullTile(true);
			cta_progress.NextTile();

			// Process any further full tiles
			while (cta_progress.HasTile()) {
				ProcessFullTile(false);
				cta_progress.NextTile();
			}

			if (cta_progress.extra_elements) {
				// Clean up last partial tile with guarded-io
				ProcessPartialTile(false);
			}

			// Collectively reduce accumulator from each thread into output
			// destination (all thread have valid reduction partials)
			OutputToSpine(KernelPolicy::TILE_ELEMENTS);

		} else if (cta_progress.extra_elements) {

			// Clean up last partial tile with guarded-io (first tile)
			ProcessPartialTile(true);

			// Collectively reduce accumulator from each thread into output
			// destination (not every thread may have a valid reduction partial)
			OutputToSpine(cta_progress.extra_elements);
		}
	}
};


} // namespace reduction
} // namespace b40

