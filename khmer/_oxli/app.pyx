from __future__ import print_function
import argparse
import itertools
import os
import sys

from .._khmer import Countgraph
from .._khmer import Nodegraph
from khmer.khmer_args import build_counting_args, create_countgraph
from khmer.khmer_logger import (configure_logging, log_info, log_error,
                                log_warn)

from libcpp cimport bool

from partitioning cimport StreamingPartitioner, Component
from partitioning import StreamingPartitioner, Component

from parsing cimport BrokenPairedReader, SplitPairedReader, FastxParser, Sequence
from parsing import BrokenPairedReader, SplitPairedReader, FastxParser, Sequence

def grouper(n, iterable):
    iterable = iter(iterable)
    return iter(lambda: list(itertools.islice(iterable, n)), [])

cdef class PartitioningApp:

    def __init__(self, args=sys.argv[1:]):
        self.args = self.parse_args(args)
        self.args.write_stats = self.args.stats_interval > 0

        self.graph = create_countgraph(self.args)
        self.partitioner = StreamingPartitioner(self.graph, tag_density=self.args.tag_density)

    def parse_args(self, args):
        parser = build_counting_args(descr='Partition a sample',
                                     citations=['counting', 'SeqAn'])
        parser.add_argument('--stats-dir', default='component-stats')
        parser.add_argument('samples', nargs='+')
        parser.add_argument('--save', default=None)
        parser.add_argument('--pairing-mode', 
                            choices=['split', 'interleaved', 'single'],
                            default='split')
        parser.add_argument('-Z', dest='norm', default=10, type=int)
        parser.add_argument('--stats-interval', default=0, type=int)
        parser.add_argument('--tag-density', default=None, type=int)
        
        return parser.parse_args(args)

    def write_components(self, folder, n, sample, new_kmers):
        sample = os.path.basename(sample)
        filename = os.path.join(folder,
                                '{0}.{1}.stats.csv'.format(n, sample))
        print('# {0}: {1} tags, {2} components.'.format(n, self.partitioner.n_tags, 
                                                        self.partitioner.n_components))
        print('  writing results to file -> {0}'.format(filename))
        self.partitioner.write_components(filename)
        with open(os.path.join(folder, 'global-stats.csv'), 'a') as fp:
            fp.write('{0}, {1}, {2}, {3}\n'.format(n, self.partitioner.n_components,
                                                 self.partitioner.n_tags, new_kmers))

    def run(self):

        if self.args.write_stats:
            try:
                os.mkdir(self.args.stats_dir)
            except OSError as e:
                pass

        if self.args.pairing_mode == 'split':
            samples = list(grouper(2, self.args.samples))
            for pair in samples:
                if len(pair) != 2:
                    raise ValueError('Must have even number of samples!')
        else:
            samples = self.args.samples
        
        cdef int n
        cdef bool paired
        cdef Sequence first, second
        cdef int new_kmers = 0
        last = 0
        for group in samples:
            if self.args.pairing_mode == 'split':
                sample_name = '{0}.{1}'.format(group[0], group[1])
                print('== Starting ({0}) =='.format(sample_name))
                reader = SplitPairedReader(FastxParser(group[0]),
                                           FastxParser(group[1]),
                                           min_length=self.args.ksize)
            else:
                sample_name = group
                print('== Starting {0} =='.format(sample_name))
                reader = BrokenPairedReader(FastxParser(group), min_length=self.args.ksize)
            for n, paired, first, second in reader:

                if n % 10000 == 0:
                    print (n, self.partitioner.n_components, self.partitioner.n_tags)
                if self.args.write_stats and n > 0 and n % self.args.stats_interval == 0:
                    self.write_components(self.args.stats_dir, last+n, sample_name, new_kmers)
                    new_kmers = 0
                if paired:
                    new_kmers += self.partitioner.consume_pair(first.sequence,
                                                  second.sequence)
                else:
                    new_kmers += self.partitioner.consume(first.sequence)
            last = n
            if self.args.write_stats:
                self.write_components(self.args.stats_dir, last, sample_name, new_kmers)
                new_kmers = 0

        if self.args.save is not None:
            self.partitioner.save(self.args.save)

        return self.partitioner