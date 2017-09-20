#!/usr/bin/env python

# Named profile_.py not to clash with cProfile doing bad absolute imports.
# Add "# cython: profile=True, linetrace=True, binding=True" directive in
# autoroutes.pyx to profile, remove autoroutes.c and autoroutes.xxx.so

from cProfile import runctx
import pstats

import pyximport
pyximport.install()

from autoroutes import Routes  # noqa (we need pyximport.install)


PATHS = ['/user/', '/user/{id}', '/user/{id}/subpath', '/user/{id}/subpath2',
         '/boat/', '/boat/{id}', '/boat/{id}/subpath', '/boat/{id}/subpath2',
         '/horse/', '/horse/{id}', '/horse/{id}/subpath',
         '/horse/{id}/subpath2', '/bicycle/', '/bicycle/{id}',
         '/bicycle/{id}/subpath2', '/bicycle/{id}/subpath']

routes = Routes()
for path in PATHS:
    routes.add(path, data='data')


runctx('for i in range(100000):\n routes.match("/horse/22/subpath")',
       globals(), locals(), 'Profile.prof')

s = pstats.Stats('Profile.prof')
s.strip_dirs().sort_stats('time').print_stats()
