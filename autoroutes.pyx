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
        if string1[i] != string2[i]:
            return i
    else:
        return bound


@cython.final
cdef class Edge:
    cdef public str pattern
    cdef public str regex
    cdef int placeholder_start
    cdef int placeholder_end
    cdef unsigned int pattern_len
    cdef public str prefix
    cdef public str suffix
    cdef unsigned int prefix_len
    cdef unsigned int suffix_len
    cdef public Node child
    cdef public unsigned int match_type

    def __init__(self, pattern, child):
        self.pattern = pattern
        self.child = child
        self.compile()

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
        self.compile()

    cdef Node join(self, str path):
        cdef:
            unsigned int local_index, candidate_index
            Edge candidate = Edge(path, None)
        local_index, candidate_index = self.compare(candidate)
        del candidate
        if not local_index:
            return None
        if local_index < self.pattern_len:
            self.branch_at(local_index)
        if candidate_index < len(path):
            return self.child.insert(path[candidate_index:])
        return self.child

    cdef tuple compare(self, Edge other):
        cdef unsigned int common_len
        if self.prefix_len and other.prefix_len:
            common_len = common_root_len(self.prefix, other.prefix)
            if not common_len:  # Nothing common.
                return 0, 0
            # At least one prefix is not finished, no need to compare further.
            elif common_len < self.prefix_len or common_len < other.prefix_len:
                return common_len, common_len
        elif self.prefix_len or other.prefix_len:
            return 0, 0
        # We now know prefix are either none or equal.
        if not self.match_type or self.match_type == MATCH_REGEX or self.match_type != other.match_type:
            return self.prefix_len, other.prefix_len
        # We now know match types are mergeable, let's see if we should also deal with suffix.
        if self.suffix and other.suffix:
            common_len = common_root_len(self.suffix, other.suffix)
            if common_len:
                return self.placeholder_end + common_len + 1, other.placeholder_end + common_len + 1
        return self.placeholder_end + 1, other.placeholder_end + 1

    cpdef str compile(self):
        """Compute and cache pattern properties.

        Eg. with pattern="foo{id}bar", we would have
        prefix=foo
        suffix=bar
        placeholder_start=3
        placeholder_end=6
        """
        cdef:
            list parts
            str match_type_or_regex = DEFAULT_MATCH_TYPE
        self.placeholder_start = self.pattern.find('{')  # Slow, but at compile it's ok.
        self.placeholder_end = self.pattern.find('}')
        self.pattern_len = len(self.pattern)
        self.prefix = self.pattern[:self.placeholder_start] if self.placeholder_start != -1 else self.pattern
        self.prefix_len = len(self.prefix)
        if self.placeholder_end != -1 and <unsigned>self.placeholder_end < self.pattern_len:
            self.suffix = self.pattern[self.placeholder_end+1:]
            self.suffix_len = len(self.suffix)
        else:
            self.suffix = None
            self.suffix_len = 0
        if self.placeholder_start != -1 and self.placeholder_end != -1:
            segment = self.pattern[self.placeholder_start:self.placeholder_end]
            parts = segment.split(':')
            if len(parts) == 2:
                match_type_or_regex = parts[1]
            if match_type_or_regex in MATCH_TYPES:
                self.match_type = MATCH_TYPES.get(match_type_or_regex)
                self.regex = PATTERNS.get(self.match_type)
            else:
                self.match_type = MATCH_REGEX
                self.regex = match_type_or_regex
        else:
            self.regex = self.pattern
            self.match_type = 0  # Reset, in case of branching.

    cdef unsigned int match(self, str path, unsigned int path_len, list params):
        cdef:
            unsigned int i = 0
        if not self.match_type:
            # Flat match.
            if path.startswith(self.pattern):
                return self.pattern_len
            return 0
        # Placeholder is not at the start (eg. "foo.{ext}").
        if self.placeholder_start > 0:
            if not self.prefix == path[:self.placeholder_start]:
                return 0
        if self.match_type == MATCH_ALL:
            i = path_len
        elif self.match_type == MATCH_NOSLASH:
            for i in range(self.placeholder_start, path_len):
                if path[i] == '/':
                    break
            else:
                i = path_len
        elif self.match_type == MATCH_ALPHA:
            for i in range(self.placeholder_start, path_len):
                if not path[i].isalpha():
                    break
            else:
                i = path_len
        elif self.match_type == MATCH_DIGIT:
            for i in range(self.placeholder_start, path_len):
                if not path[i].isdigit():
                    break
            else:
                i = path_len
        elif self.match_type == MATCH_ALNUM:
            for i in range(self.placeholder_start, path_len):
                if not path[i].isalnum():
                    break
            else:
                i = path_len
        elif self.match_type == MATCH_NODASH:
            for i in range(self.placeholder_start, path_len):
                if path[i] == '-':
                    break
            else:
                i = path_len
        if i:
            params.append(path[self.placeholder_start:i])  # Slow.
            if self.suffix_len:
                # The placeholder is not at the end (eg. "{name}.json").
                if path[i:i+self.suffix_len] != self.suffix:
                    return 0
                i = i + self.suffix_len
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
                    edge = self.edges[matched.lastindex-1]
                    if edge.placeholder_start != -1:  # Is the capture a slug value?
                        params.append(matched.group(matched.lastindex))
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
                pattern += '^({})'.format(edge.regex)
                if edge.pattern.find('{') != -1:
                    if edge.match_type == MATCH_REGEX:
                        has_slug = True
                if i + 1 < total:
                    pattern += '|'

            # Run in regex mode only if we have a non optimizable pattern.
            if has_slug:
                self.pattern = pattern
                self.regex = re.compile(pattern)

    cdef Node insert(self, str path):
        cdef:
            Node node
            Edge edge = None
            str prefix
            int bound, end
            unsigned int nb_slugs

        node = self.common_edge(path)

        if node:
            return node

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
                if edge.match_type == MATCH_REGEX:  # Non optimizable, split if pattern has prefix or suffix.
                    if start > 0:  # slug does not start at first char (eg. foo{slug})
                        edge.branch_at(start)
                    end = path.find('}')
                    if end + 1 < len(path):  # slug does not end pattern (eg. {slug}foo)
                        edge.branch_at(end + 1)
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
                pattern = edge.prefix + edge.regex + edge.suffix or ''
            else:
                pattern = edge.pattern
            print(f'{i}' + '\--- %s' % pattern)
            if edge.child:
                dump(edge.child, level + 1)
