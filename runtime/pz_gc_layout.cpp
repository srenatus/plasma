/*
 * Plasma garbage collector memory layout
 * vim: ts=4 sw=4 et
 *
 * Copyright (C) 2019 Plasma Team
 * Distributed under the terms of the MIT license, see ../LICENSE.code
 */

#include "pz_common.h"

#include <string.h>

#include "pz_util.h"

#include "pz_gc.h"
#include "pz_gc_util.h"

#include "pz_gc.impl.h"
#include "pz_gc_layout.h"

namespace pz {

static LBlock *
ptr_to_lblock(void *ptr)
{
    return reinterpret_cast<LBlock*>(
        reinterpret_cast<uintptr_t>(ptr) & GC_LBLOCK_MASK);
}

CellPtr::CellPtr(LBlock *block, unsigned index) :
    m_block(block), m_index(index)
{
    m_ptr = block->index_to_pointer(index);
}

CellPtr::CellPtr(void* ptr) :
    m_ptr(reinterpret_cast<void**>(ptr))
{
    m_block = ptr_to_lblock(ptr);
    m_index = m_block->index_of(ptr);
}

bool
LBlock::is_in_payload(const void *ptr) const
{
    return ptr >= m_bytes && ptr < &m_bytes[PAYLOAD_BYTES];
}

bool
LBlock::is_valid_address(const void *ptr) const
{
    assert(is_in_use());

    return is_in_payload(ptr) &&
        ((reinterpret_cast<size_t>(ptr) - reinterpret_cast<size_t>(m_bytes)) %
            (size() * WORDSIZE_BYTES)) == 0;
}

unsigned
LBlock::index_of(const void *ptr) const {
    assert(is_valid_address(ptr));

    return (reinterpret_cast<size_t>(ptr) - reinterpret_cast<size_t>(m_bytes)) /
        (size() * WORDSIZE_BYTES);
}

void **
LBlock::index_to_pointer(unsigned index)
{
    assert(index < num_cells());

    unsigned offset = index * size() * WORDSIZE_BYTES;
    assert(offset + size() <= PAYLOAD_BYTES);

    return reinterpret_cast<void**>(&m_bytes[offset]);
}

/*
 * TODO: Can the const and non-const versions somehow share an
 * implementation?  Would that actually save any code lines?
 */

const uint8_t *
LBlock::cell_bits(const CellPtr &cell) const
{
    assert(cell.isValid() && cell.lblock() == this);
    return cell_bits(cell.index());
}

const uint8_t *
LBlock::cell_bits(unsigned index) const
{
    assert(index < num_cells());
    return &(m_header.bitmap[index]);
}

uint8_t *
LBlock::cell_bits(const CellPtr &cell)
{
    assert(cell.isValid() && cell.lblock() == this);
    return cell_bits(cell.index());
}

uint8_t *
LBlock::cell_bits(unsigned index)
{
    assert(index < num_cells());
    return &(m_header.bitmap[index]);
}

bool
LBlock::is_allocated(CellPtr &cell) const
{
    return *cell_bits(cell) & GC_BITS_ALLOCATED;
}

bool
LBlock::is_marked(CellPtr &cell) const
{
    return *cell_bits(cell) & GC_BITS_MARKED;
}

void
LBlock::mark(CellPtr &cell)
{
    *cell_bits(cell) |= GC_BITS_MARKED;
}

bool
Heap::is_heap_address(void *ptr) const
{
    if (!m_bblock->contains_pointer(ptr)) return false;

    LBlock *lblock = ptr_to_lblock(ptr);

    if (!lblock->is_in_use()) return false;
    return lblock->is_in_payload(ptr);
}

bool
Heap::is_valid_cell(void *ptr) const
{
    if (!is_heap_address(ptr)) return false;

    LBlock *lblock = ptr_to_lblock(ptr);

    if (!lblock->is_in_use()) return false;
    return lblock->is_valid_address(ptr);
}

CellPtr
Heap::ptr_to_cell(void *ptr) const
{
    assert(is_valid_cell(ptr));

    return CellPtr(ptr);
}

} // namespace pz
