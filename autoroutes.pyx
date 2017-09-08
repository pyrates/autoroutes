# cython: language_level=3
cimport cython
from cpython cimport bool
import re


# TODO: raise if not match.
# This ends with slower code (because
# of the try/except) so maybe it should
# be optional.
class NoRoute(Exception):
    ...


class InvalidRoute(Exception):
    ...


cdef enum:
    OP_EXPECT_MORE_DIGITS = 1, OP_EXPECT_MORE_WORDS, OP_EXPECT_NOSLASH, OP_EXPECT_NODASH, OP_EXPECT_MORE_ALPHA, OP_EXPECT_ALL
    DASH = 45, SLASH = 47  # ord(b'-'), ord(b'/')

NOSLASH = b'[^/]+'

OPCODES = {
    b'\w+': OP_EXPECT_MORE_WORDS,
    b'w': OP_EXPECT_MORE_WORDS,
    b'word': OP_EXPECT_MORE_WORDS,
    b'[0-9a-z]+': OP_EXPECT_MORE_WORDS,
    b'[a-z0-9]+': OP_EXPECT_MORE_WORDS,
    b'[a-z]+': OP_EXPECT_MORE_ALPHA,
    b'\d+': OP_EXPECT_MORE_DIGITS,
    b'i': OP_EXPECT_MORE_DIGITS,
    b'int': OP_EXPECT_MORE_DIGITS,
    b'[0-9]+': OP_EXPECT_MORE_DIGITS,
    NOSLASH: OP_EXPECT_NOSLASH,
    b'string': OP_EXPECT_NOSLASH,
    b's': OP_EXPECT_NOSLASH,
    b'[^-]+': OP_EXPECT_NODASH,
    b'.+': OP_EXPECT_ALL,
    b'*': OP_EXPECT_ALL,
    b'path': OP_EXPECT_ALL,
}


@cython.final
cdef class Edge:
    cdef public bytes pattern
    cdef int pattern_start
    cdef int pattern_end
    cdef unsigned int pattern_len
    cdef bytes pattern_prefix
    cdef bytes pattern_suffix
    cdef unsigned int pattern_suffix_len
    cdef public Node child
    cdef public unsigned int opcode

    def __cinit__(self, pattern, child):
        self.pattern = pattern
        self.child = child

    cdef branch_at(self, unsigned int prefix_len):
        cdef:
            Node new_child = Node()
            bytes rest = self.pattern[prefix_len:]
        new_child.connect(self.child, rest)
        self.child = new_child
        self.pattern = self.pattern[:prefix_len]

    cpdef bytes compile(self):
        self.pattern_start = self.pattern.find(b'{')  # Slow, but at compile it's ok.
        self.pattern_end = self.pattern.find(b'}')
        self.pattern_len = len(self.pattern)
        if self.pattern_start > 0:
            self.pattern_prefix = self.pattern[:self.pattern_start]
        if self.pattern_end != -1 and <unsigned>self.pattern_end < self.pattern_len:
            self.pattern_suffix = self.pattern[self.pattern_end+1:]
            self.pattern_suffix_len = len(self.pattern_suffix)
        cdef:
            list parts
            bytes pattern, segment
        if self.pattern_start != -1 and self.pattern_end != -1:
            segment = self.pattern[self.pattern_start:self.pattern_end]
            parts = segment.split(b':')
            if len(parts) == 2:
                pattern = parts[1]
            else:
                pattern = NOSLASH
            if pattern in OPCODES:
                self.opcode = OPCODES[pattern]
        else:
            pattern = self.pattern
        return pattern

    cdef unsigned int match(self, const char *path, unsigned int path_len, list params):
        cdef:
            unsigned int i = 0
        if not self.opcode:
            # Flat match.
            if path.startswith(self.pattern):
                return self.pattern_len
            return 0
        # Placeholder is not at the start (eg. "foo.{ext}").
        if self.pattern_start > 0:
            if not self.pattern_prefix == path[:self.pattern_start]:
                return 0
        if self.opcode == OP_EXPECT_ALL:
            i = path_len
        elif self.opcode == OP_EXPECT_NOSLASH:
            for i in range(self.pattern_start, path_len):
                if path[i] == SLASH:
                    break
            else:
                if i:
                    i = path_len
        elif self.opcode == OP_EXPECT_MORE_ALPHA:
            for i in range(self.pattern_start, path_len):
                if not chr(path[i]).isalpha():
                    break
            else:
                if i:
                    i = path_len
        elif self.opcode == OP_EXPECT_MORE_DIGITS:
            for i in range(self.pattern_start, path_len):
                if not chr(path[i]).isdigit():
                    break
            else:
                if i:
                    i = path_len
        elif self.opcode == OP_EXPECT_MORE_WORDS:
            for i in range(self.pattern_start, path_len):
                if not chr(path[i]).isdigit() and not chr(path[i]).isalpha():
                    break
            else:
                if i:
                    i = path_len
        elif self.opcode == OP_EXPECT_NODASH:
            for i in range(self.pattern_start, path_len):
                if path[i] == DASH:
                    break
            else:
                if i:
                    i = path_len
        if i:
            params.append(path[self.pattern_start:i])  # Slow.
            if self.pattern_suffix and i < self.pattern_len:
                # The placeholder is not at the end (eg. "{name}.json").
                if path[i:i+self.pattern_suffix_len] != self.pattern_suffix:
                    return 0
                i = i+self.pattern_suffix_len
        return i


cdef class Node:
    cdef public object payload
    cdef public list edges
    cdef public bytes path
    cdef public object regex
    cdef public bytes pattern
    cdef public list slugs
    cdef unsigned int slugs_count
    SLUGS = re.compile(b'{([^:}]+).*?}')

    cdef void attach_route(self, const char *path, object payload):
        self.slugs = Node.SLUGS.findall(path)
        self.slugs_count = len(self.slugs)
        self.path = path
        self.payload = payload

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

    cdef common_prefix(self, const char *path):
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
                        if b'{' in path[:i] and not b'}' in path[:i]:
                            i = path.find(b'{')
                        break
                else:
                    i = bound
                if i:
                    return edge, path[:i]
        return None, None

    cdef Edge match(self, const char *path, list params):
        cdef:
            unsigned int path_len = len(path)
            unsigned int match_len
            bytes match
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
            unsigned int count = 0
            bool has_slug = False
            bytes pattern = b''
            unsigned int total = 0
            Edge edge
        if self.edges:
            total = len(self.edges)
            for i, edge in enumerate(self.edges):
                # compile "foo/{slug}" to "foo/[^/]+"
                pattern += b'^(%b)' % edge.compile()
                if edge.pattern.find(b'{') != -1:  # TODO validate {} pairs.
                    if edge.opcode:
                        count += 1
                    else:
                        has_slug = True
                if i+1 < total:
                    pattern += b'|'

            # Run in regex mode only if we have a non optimizable pattern.
            if has_slug:
                self.pattern = pattern
                self.regex = re.compile(pattern)


cdef class Routes:

    cdef Node root

    def __cinit__(self):
        self.root = Node()

    def connect(self, bytes path, **payload):
        cdef Node node
        if path.count(b'{') != path.count(b'}'):
            raise InvalidRoute('Unbalanced curly brackets for "{path}"'.format(path=path))
        node = self.insert(self.root, path)
        node.attach_route(path, payload)
        self.compile()

    def follow(self, bytes path):
        return self.match(path)

    cdef tuple match(self, bytes path):
        cdef:
            list values = []
            dict params = {}
            list slugs
            unsigned int i
        edge = self.root.match(path, values)
        if edge:
            # FIXME: more than 30% time lost in computing params.
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
                if edge.opcode:
                    print(f'{i} |    opcode: %d' % edge.opcode)
                if edge.child:
                    self._dump(edge.child, level + 1)

    def compile(self):
        self._compile(self.root)

    cdef _compile(self, Node node):
        cdef:
            Edge edge
        node.compile()
        if node.edges:
            for edge in node.edges:
                self._compile(edge.child)

    cdef Node insert(self, Node tree, const char *path):
        cdef:
            Node node = tree
            # common edge
            Edge edge = None
            bytes prefix
            int bound, end
            unsigned int nb_slugs

        # If there is no path to insert at the node, we just increase the mount
        # point on the node and append the route.
        if not len(path):
            return tree

        edge, prefix = node.common_prefix(path)

        if not edge:
            nb_slugs = path.count(b'{')
            start = path.find(b'{')
            if nb_slugs > 1:
                # Break into parts
                child = Node()
                start = path.find(b'{', start + 1)  # Goto the next one.
                node.connect(child, path[:start])
                return self.insert(child, path[start:])
            else:
                child = Node()
                edge = node.connect(child, path)
                if nb_slugs:
                    edge.compile()
                    if not edge.opcode:  # Non optimizable, we may need to split.
                        # slug does not start at first char (eg. foo{slug})
                        if start > 0:
                            edge.branch_at(start)
                        end = path.find(b'}')
                        # slug does not end pattern (eg. {slug}foo)
                        if end+1 < len(path):
                            edge.branch_at(end+1)
                return child
        elif len(prefix) == len(edge.pattern):
            if len(path) > len(prefix):
                return self.insert(edge.child, path[len(prefix):])
            return edge.child
        elif len(prefix) < len(edge.pattern):
            edge.branch_at(len(prefix))
            return self.insert(edge.child, path[len(prefix):])
