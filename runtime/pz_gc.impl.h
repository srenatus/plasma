/*
 * Plasma garbage collector
 * vim: ts=4 sw=4 et
 *
 * Copyright (C) 2018-2019 Plasma Team
 * Distributed under the terms of the MIT license, see ../LICENSE.code
 */

#ifndef PZ_GC_IMPL_H
#define PZ_GC_IMPL_H

#include "pz_util.h"
#include "pz_gc.h"
#include "pz_gc_util.h"

namespace pz {

class CellPtr;
class CellPtrBOP;
class CellPtrFit;
class Block;
class ChunkBOP;
class ChunkFit;

class Heap {
  private:
    const Options      &m_options;

    static size_t       s_page_size;

    // For now there's exactly two chunks: one for small allocations
    // (big bag of pages aka "bop"), and one for medium sized allocations
    // (best fit with splitting). (Big allocations will be implemented
    // later).
    ChunkBOP*           m_chunk_bop;
    ChunkFit*           m_chunk_fit;

    size_t              m_usage;
    size_t              m_threshold;
    unsigned            m_collections;

    AbstractGCTracer   &m_trace_global_roots;

  public:
    Heap(const Options &options, AbstractGCTracer &trace_global_roots);
    ~Heap();

    static void init_statics();

    bool init();
    bool finalise();

    enum AllocOpts {
        NORMAL,
        META
    };

    void * alloc(size_t size_in_words, GCCapability &gc_cap, AllocOpts opts);
    void * alloc_bytes(size_t size_in_bytes, GCCapability &gc_cap,
        AllocOpts opts);

    /*
     * Note that usage is an over-estimate, it can contain block-internal
     * fragmentation.
     */
    size_t usage() const { return m_usage; };

    unsigned collections() const { return m_collections; }

    Heap(const Heap &) = delete;
    Heap& operator=(const Heap &) = delete;

    /*
     * This is not guarenteed to collect, for now we have no logic to decide
     * if we want to collect, just do it.
     */
    void maybe_collect(const AbstractGCTracer *thread_tracer) {
        collect(thread_tracer);
    }

    void set_meta_info(void *obj, void *meta);

    void * meta_info(void *obj) const;

  private:
    void collect(const AbstractGCTracer *thread_tracer);

    bool is_empty() const { return usage() == 0; };

    // Returns the number of cells marked recursively.
    template<typename Cell>
    unsigned mark(Cell &cell);

    unsigned mark_field(void *ptr);

    // Specialised for marking specific cell types.  Returns the size of the
    // cell.
    static unsigned do_mark(CellPtrBOP &cell);
    static unsigned do_mark(CellPtrFit &cell);
    
    unsigned do_mark_special_field(CellPtrBOP &cell);
    unsigned do_mark_special_field(CellPtrFit &cell);

    void sweep();

    void * try_allocate(size_t size_in_words);
    void * try_small_allocate(size_t size_in_words);
    void * try_medium_allocate(size_t size_in_words);

    Block * get_block_for_allocation(size_t size_in_words);

    Block * allocate_block(size_t size_in_words);

    /*
     * Although these two methods are marked as inline they are defined in
     * pz_gc_layout.h with other inline functions.
     */

    // The address points to memory within the heap (is inside the payload
    // of an actively used block).
    inline bool is_heap_address(void *ptr) const;

    // An address can be converted to a cell here, or Invalid() if the
    // address isn't the first address of a valid cell.
    CellPtrBOP ptr_to_bop_cell(void *ptr) const;
    CellPtrBOP ptr_to_bop_cell_interior(void *ptr) const;
    CellPtrFit ptr_to_fit_cell(void *ptr) const;
    CellPtrFit ptr_to_fit_cell_interior(void *ptr) const;

    friend class HeapMarkState;

  public:
    void * interior_ptr_to_ptr(void *ptr) const;

#ifdef PZ_DEV
  private:
    friend class NoGCScope;
    bool m_in_no_gc_scope;
    void start_no_gc_scope();
    void end_no_gc_scope();

    void check_heap() const;
    void print_usage_stats(size_t initial_usage) const;

    /*
     * This is not used anywhere, it's included so it can be run from gdb to
     * help with debugging.
     */
    void print_addr_info(void *addr) const;
#endif
};

} // namespace pz

#endif // ! PZ_GC_IMPL_H
