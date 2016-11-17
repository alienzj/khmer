from libcpp.memory cimport unique_ptr, weak_ptr, shared_ptr
from libcpp.vector cimport vector
from libc.stdint cimport uint32_t, uint8_t, uint64_t

from _oxli cimport ComponentPtr, ComponentPtrSet, CpGuardedKmerCompMap
from _oxli cimport CpHashtable, CpStreamingPartitioner, BoundedCounterType


cdef class Component:
    cdef ComponentPtr _this

    @staticmethod
    cdef Component wrap(ComponentPtr ptr)

    @staticmethod
    cdef vector[BoundedCounterType] _tag_counts(ComponentPtr comp, CpHashtable * graph)

    @staticmethod
    cdef float _mean_tag_count(ComponentPtr comp, CpHashtable * graph)


cdef class StreamingPartitioner:
    cdef unique_ptr[CpStreamingPartitioner] _this
    cdef weak_ptr[ComponentPtrSet] _components
    cdef weak_ptr[CpGuardedKmerCompMap] _tag_component_map
    cdef CpHashtable * _graph_ptr
    cdef readonly uint64_t n_consumed