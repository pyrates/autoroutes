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
PATTERNS = {
    MATCH_ALL: '.+',
    MATCH_ALNUM: '\w+',
    MATCH_ALPHA: '[a-zA-Z]+',
    MATCH_DIGIT: '\d+',
    MATCH_NOSLASH: '[^/]+',
}


cdef int common_root_len(string1, string2):
    cdef unsigned int bound, i
    bound = min(len(string1), len(string2))
    for i in range(bound):
        if path[i] != self.pattern[i]:
            return i
    else:
        return bound


@cython.final
cdef class Edge:
    cdef public str pattern
    cdef int pattern_start
    cdef int pattern_end
    cdef unsigned int pattern_len
    cdef str pattern_prefix
    cdef str pattern_suffix
    cdef unsigned int pattern_prefix_len
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
        new_child.compile()
        self.pattern = self.pattern[:prefix_len]

    cpdef Node join(self, str path):
        cdef:
            unsigned int common_len
            unsigned int path_len = len(path)
            Edge candidate = Edge(path, None)
        candidate.compile()
        if self.pattern_prefix_len and candidate.pattern_prefix_len:
            common_len = common_root_len(self.pattern_prefix, candidate.pattern_prefix)
            if not common_len:  # Nothing common.
                return None
            elif common_len < self.pattern_prefix_len:  # Remote prefix is consumed but not self.
                self.branch_at(common_len)
                return self.child.insert(path[common_len:])
            elif common_len < candidate.pattern_prefix_len:  # Self prefix is consumed but not remote.
                if self.match_type:
                    self.branch_at(common_len)
                return self.child.insert(path[common_len:])
            # else prefix are equal and fully consumed.
        elif self.pattern_prefix_len or candidate.pattern_prefix_len:
            return None
        # We now know prefix are either none or equal.
        if not self.match_type and not candidate.match_type:
            # No placeholder, thus no suffix, we're done.
            if self.pattern_prefix_len:
                return self.child
            return None
        elif not self.match_type:
            return self.child.insert(path[self.pattern_prefix_len:])
        elif not candidate.match_type or self.match_type == MATCH_REGEX or self.match_type != candidate.match_type:
            # We cannot merge placeholders.
            if self.pattern_prefix_len:
                self.branch_at(self.pattern_start)
                return self.child.insert(path[candidate.pattern_prefix_len:])
            else:  # Nothing matched, abort.
                return None
        else:  # match types are mergeable, let's see if we should also deal with suffix.
            if not self.pattern_suffix and not candidate.pattern_suffix:
                return self.child
            elif not self.pattern_suffix:
                return self.child.insert(path[candidate.pattern_end:])
            elif not candidate.pattern_suffix:
                self.branch_at(self.pattern_end)
                return self.child.insert(path[candidate.pattern_end:])
            else:
                common_len = common_root_len(self.pattern_suffix, candidate.pattern_suffix)
                if not common_len:  # Nothing common in the suffix.
                    return self.child.insert(path[candidate.pattern_end+1:])
                elif common_len == self.pattern_suffix_len == candidate.pattern_suffix_len:
                    return self.child
                elif common_len < self.pattern_suffix_len:  # Remaining self suffix.
                    self.branch_at(self.pattern_end+common_len+1)
                    if candidate.pattern_end+common_len+1 < candidate.pattern_len:
                        return self.child.insert(path[candidate.pattern_end+common_len+1:])
                    return self.child
                elif common_len < candidate.pattern_suffix_len:  # Remaining candidate suffix.
                    return self.child.insert(path[candidate.pattern_end+common_len+1:])
                # else:  # The whole self suffix is consumed and both are equal.

    cpdef str compile(self):
        self.pattern_start = self.pattern.find('{')  # Slow, but at compile it's ok.
        self.pattern_end = self.pattern.find('}')
        self.pattern_len = len(self.pattern)
        self.pattern_prefix = self.pattern[:self.pattern_start] if self.pattern_start != -1 else self.pattern
        self.pattern_prefix_len = len(self.pattern_prefix)
        if self.pattern_end != -1 and <unsigned>self.pattern_end < self.pattern_len:
            self.pattern_suffix = self.pattern[self.pattern_end+1:]
            self.pattern_suffix_len = len(self.pattern_suffix)
        else:
            self.pattern_suffix = None
            self.pattern_suffix_len = 0
        cdef:
            list parts
            str pattern, segment
            unsigned int match_type
        if self.pattern_start != -1 and self.pattern_end != -1:
            pattern, self.match_type = Edge.extract_pattern(self.pattern[self.pattern_start:self.pattern_end])
        else:
            pattern = self.pattern
            self.match_type = 0  # Reset, in case of branching.
        return pattern

    @staticmethod
    cdef tuple extract_pattern(str segment):
        cdef:
            list parts
            unsigned int match_type
        parts = segment.split(':')
        if len(parts) == 2:
            pattern = parts[1]
        else:
            pattern = DEFAULT_MATCH_TYPE
        match_type = MATCH_TYPES.get(pattern, MATCH_REGEX)
        return pattern, match_type

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
                if path[i:i+self.pattern_suffix_len] != self.pattern_suffix:
                    return 0
                i = i+self.pattern_suffix_len
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

    cdef Node common_edge(self, str path):
        cdef:
            Edge edge
            Node node
        if self.edges:
            for edge in self.edges:
                node = edge.join(path)
                if node:
                    return node

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
                    edge = self.edges[matched.lastindex-1]
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
                if i+1 < total:
                    pattern += '|'

            # Run in regex mode only if we have a non optimizable pattern.
            if has_slug:
                self.pattern = pattern
                self.regex = re.compile(pattern)

    cdef Node insert(self, str path):
        cdef:
            Node node
            # common edge
            Edge edge = None
            str prefix
            int bound, end
            unsigned int nb_slugs

        print(f'Node.insert "{path}"')
        # If there is no path to insert at the node, we just increase the mount
        # point on the node and append the route.
        if not len(path):
            print('No path, aborting insert')
            return self

        node = self.common_edge(path)

        if node:
            print('Found a common edge', path, node)
            return node

        print('No node found, create a new one')

        nb_slugs = path.count('{')
        start = path.find('{')
        if nb_slugs > 1:
            # Break into parts
            child = Node()
            start = path.find('{', start + 1)  # Goto the next one.
            self.connect(child, path[:start])
            return child.insert(path[start:])
        else:
            child = Node()
            edge = self.connect(child, path)
            if nb_slugs:
                edge.compile()
                if edge.match_type == MATCH_REGEX:  # Non optimizable, split if pattern has prefix or suffix.
                    if start > 0:  # slug does not start at first char (eg. foo{slug})
                        edge.branch_at(start)
                    end = path.find('}')
                    if end+1 < len(path):  # slug does not end pattern (eg. {slug}foo)
                        edge.branch_at(end+1)
            return child


cdef class Routes:

    cdef public Node root

    def __cinit__(self):
        self.root = Node()

    def add(self, str path, **payload):
        cdef Node node
        if path.count('{') != path.count('}'):
            raise InvalidRoute('Unbalanced curly brackets for "{path}"'.format(path=path))
        node = self.root.insert(path)
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
        dump(self.root)

    cdef compile(self, Node node):
        cdef:
            Edge edge
        node.compile()
        if node.edges:
            for edge in node.edges:
                self.compile(edge.child)


cdef dump(node, level=0):
    types = {v: k for k, v in MATCH_TYPES.items()}
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
            if edge.match_type:
                print(f'{i}' + '\--- {%s}' % types.get(edge.match_type))
            else:
                print(f'{i}' + '\--- %s' % edge.pattern)
            if edge.child:
                dump(edge.child, level + 1)
