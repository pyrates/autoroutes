# cython: language_level=3
cimport cython
from cpython cimport bool
import re


class InvalidRoute(Exception):
    ...


cdef enum:
    MATCH_DIGIT = 1, MATCH_ALNUM, MATCH_NOSLASH, MATCH_NODASH, MATCH_ALPHA, MATCH_ALL, MATCH_REGEX

DEFAULT_MATCH_TYPE = 'string'  # Faster default, works for most common use case /{var}/.

MATCH_TYPES = {
    'alnum': MATCH_ALNUM,
    'alpha': MATCH_ALPHA,
    'digit': MATCH_DIGIT,
    DEFAULT_MATCH_TYPE: MATCH_NOSLASH,
    'path': MATCH_ALL,
}


@cython.final
cdef class Edge:
    cdef public str pattern
    cdef int pattern_start
    cdef int pattern_end
    cdef unsigned int pattern_len
    cdef str pattern_prefix
    cdef str pattern_suffix
    cdef unsigned int pattern_suffix_len
    cdef public Node child
    cdef public unsigned int match_type

    def __cinit__(self, pattern, child):
        self.pattern = pattern
        self.child = child

    def __repr__(self):
        return '<Edge {}>'.format(self.pattern)

    cdef branch_at(self, unsigned int prefix_len):
        cdef:
            Node new_child = Node()
            str rest = self.pattern[prefix_len:]
        new_child.connect(self.child, rest)
        self.child = new_child
        self.pattern = self.pattern[:prefix_len]

    cpdef str compile(self):
        self.pattern_start = self.pattern.find('{')  # Slow, but at compile it's ok.
        self.pattern_end = self.pattern.find('}')
        self.pattern_len = len(self.pattern)
        if self.pattern_start > 0:
            self.pattern_prefix = self.pattern[:self.pattern_start]
        else:
            self.pattern_prefix = None
        if self.pattern_end != -1 and <unsigned>self.pattern_end < self.pattern_len:
            self.pattern_suffix = self.pattern[self.pattern_end + 1:]
            self.pattern_suffix_len = len(self.pattern_suffix)
        else:
            self.pattern_suffix = None
            self.pattern_suffix_len = 0
        cdef:
            list parts
            str pattern, segment
        if self.pattern_start != -1 and self.pattern_end != -1:
            segment = self.pattern[self.pattern_start:self.pattern_end]
            parts = segment.split(':')
            if len(parts) == 2:
                pattern = parts[1]
            else:
                pattern = DEFAULT_MATCH_TYPE
            self.match_type = MATCH_TYPES.get(pattern, MATCH_REGEX)
        else:
            pattern = self.pattern
            self.match_type = 0  # Reset, in case of branching.
        return pattern

    cdef unsigned int match(self, str path, unsigned int path_len, list params):
        cdef:
            unsigned int i = 0
        if not self.match_type:
            # Flat match.
            if path.startswith(self.pattern):
                return self.pattern_len
            return 0
        # Placeholder is not at the start (eg. "foo.{ext}").
        if self.pattern_start > 0:
            if not self.pattern_prefix == path[:self.pattern_start]:
                return 0
        if self.match_type == MATCH_ALL:
            i = path_len
        elif self.match_type == MATCH_NOSLASH:
            for i in range(self.pattern_start, path_len):
                if path[i] == '/':
                    break
            else:
                if i:
                    i = path_len
        elif self.match_type == MATCH_ALPHA:
            for i in range(self.pattern_start, path_len):
                if not path[i].isalpha():
                    break
            else:
                if i:
                    i = path_len
        elif self.match_type == MATCH_DIGIT:
            for i in range(self.pattern_start, path_len):
                if not path[i].isdigit():
                    break
            else:
                if i:
                    i = path_len
        elif self.match_type == MATCH_ALNUM:
            for i in range(self.pattern_start, path_len):
                if not path[i].isalnum():
                    break
            else:
                if i:
                    i = path_len
        elif self.match_type == MATCH_NODASH:
            for i in range(self.pattern_start, path_len):
                if path[i] == '-':
                    break
            else:
                if i:
                    i = path_len
        if i:
            params.append(path[self.pattern_start:i])  # Slow.
            if self.pattern_suffix_len and i < self.pattern_len:
                # The placeholder is not at the end (eg. "{name}.json").
                if path[i:i + self.pattern_suffix_len] != self.pattern_suffix:
                    return 0
                i = i + self.pattern_suffix_len
        return i


cdef class Node:
    cdef public dict payload
    cdef public list edges
    cdef public str path
    cdef public object regex
    cdef public str pattern
    cdef public list slugs
    cdef unsigned int slugs_count
    SLUGS = re.compile('{([^:}]+).*?}')

    def __cinit__(self):
        self.payload = {}

    cdef void attach_route(self, str path, dict payload):
        self.slugs = Node.SLUGS.findall(path)
        self.slugs_count = len(self.slugs)
        self.path = path
        self.payload.update(payload)

    cdef Edge connect(self, child, pattern):
        cdef Edge edge
        if not self.edges:
            self.edges = []
        for edge in self.edges:
            if edge.pattern == pattern:
                break
        else:
            edge = Edge(pattern=pattern, child=child)
            self.edges.append(edge)
        return edge

    cdef common_prefix(self, str path):
        cdef:
            unsigned int i, bound
            unsigned int path_len = len(path)
            Edge edge
        if self.edges:
            for edge in self.edges:
                bound = min(path_len, len(edge.pattern))
                i = 0
                for i in range(bound):
                    if path[i] != edge.pattern[i]:
                        # Are we in the middle of a placeholder?
                        if '{' in path[:i] and '}' not in path[:i]:
                            i = path.find('{')
                        break
                else:
                    i = bound
                if i:
                    return edge, path[:i]
        return None, None

    cdef Edge match(self, str path, list params):
        cdef:
            unsigned int path_len = len(path)
            unsigned int match_len
            Edge edge
            object matched

        if self.edges:
            if self.pattern:
                matched = self.regex.match(path)
                if matched:
                    params.append(matched.group(matched.lastindex))
                    edge = self.edges[matched.lastindex - 1]
                    if matched.end() == path_len:
                        if edge.child.path:
                            return edge
                    else:
                        return edge.child.match(path[matched.end():], params)
            else:
                for edge in self.edges:
                    match_len = edge.match(path, path_len, params)
                    if match_len:
                        if path_len == match_len and edge.child.path:
                            return edge
                        return edge.child.match(path[match_len:], params)
        return None

    cdef void compile(self):
        cdef:
            bool has_slug = False
            str pattern = ''
            unsigned int total = 0
            Edge edge
        if self.edges:
            total = len(self.edges)
            for i, edge in enumerate(self.edges):
                pattern += '^({})'.format(edge.compile())
                if edge.pattern.find('{') != -1:
                    if edge.match_type == MATCH_REGEX:
                        has_slug = True
                if i + 1 < total:
                    pattern += '|'

            # Run in regex mode only if we have a non optimizable pattern.
            if has_slug:
                self.pattern = pattern
                self.regex = re.compile(pattern)


cdef class Routes:

    cdef Node root

    def __cinit__(self):
        self.root = Node()

    def add(self, str path, **payload):
        cdef Node node
        if path.count('{') != path.count('}'):
            raise InvalidRoute('Unbalanced curly brackets for "{path}"'.format(path=path))
        node = self.insert(self.root, path)
        node.attach_route(path, payload)
        self.compile(self.root)

    def match(self, str path):
        return self._match(path)

    cdef tuple _match(self, str path):
        cdef:
            list values = []
            dict params = {}
            list slugs
            unsigned int i
        edge = self.root.match(path, values)
        if edge:
            slugs = edge.child.slugs
            for i in range(edge.child.slugs_count):
                params[slugs[i]] = values[i]
            return edge.child.payload, params
        return None, None

    def dump(self):
        self._dump(self.root)

    cdef _dump(self, node, level=0):
        i = " " * level * 4
        print(f'{i}(o)')
        if node.pattern:
            print(f'{i}| regexp: %s' % node.pattern)
        if node.payload:
            print(f'{i}| data: %s' % node.payload)
        if node.path:
            print(f'{i}| path: %s' % node.path)
            print(f'{i}| slugs: %s' % node.slugs)
        if node.edges:
            for edge in node.edges:
                print(f'{i}' + '\--- %s' % edge.pattern)
                if edge.match_type:
                    print(f'{i} |    match_type: %d' % edge.match_type)
                if edge.child:
                    self._dump(edge.child, level + 1)

    cdef compile(self, Node node):
        cdef:
            Edge edge
        node.compile()
        if node.edges:
            for edge in node.edges:
                self.compile(edge.child)

    cdef Node insert(self, Node tree, str path):
        cdef:
            Node node = tree
            # common edge
            Edge edge = None
            str prefix
            int bound, end
            unsigned int nb_slugs

        # If there is no path to insert at the node, we just increase the mount
        # point on the node and append the route.
        if not len(path):
            return tree

        edge, prefix = node.common_prefix(path)

        if not edge:
            nb_slugs = path.count('{')
            start = path.find('{')
            if nb_slugs > 1:
                # Break into parts
                child = Node()
                start = path.find('{', start + 1)  # Goto the next one.
                node.connect(child, path[:start])
                return self.insert(child, path[start:])
            else:
                child = Node()
                edge = node.connect(child, path)
                if nb_slugs:
                    edge.compile()
                    if edge.match_type == MATCH_REGEX:  # Non optimizable, split if pattern has prefix or suffix.
                        if start > 0:  # slug does not start at first char (eg. foo{slug})
                            edge.branch_at(start)
                        end = path.find('}')
                        if end + 1 < len(path):  # slug does not end pattern (eg. {slug}foo)
                            edge.branch_at(end + 1)
                return child
        elif len(prefix) == len(edge.pattern):
            if len(path) > len(prefix):
                return self.insert(edge.child, path[len(prefix):])
            return edge.child
        elif len(prefix) < len(edge.pattern):
            edge.branch_at(len(prefix))
            return self.insert(edge.child, path[len(prefix):])
