# cython: language_level=3

from cpython cimport bool
import re


class NoRoute(Exception):
    ...


cdef enum:
    NODE_COMPARE_STR, NODE_COMPARE_PCRE, NODE_COMPARE_OPCODE
    OP_EXPECT_MORE_DIGITS = 1, OP_EXPECT_MORE_WORDS, OP_EXPECT_NOSLASH, OP_EXPECT_NODASH, OP_EXPECT_MORE_ALPHA, OP_EXPECT_ALL


OPCODES = {
    b'\w+': OP_EXPECT_MORE_WORDS,
    b'[0-9a-z]+': OP_EXPECT_MORE_WORDS,
    b'[a-z0-9]+': OP_EXPECT_MORE_WORDS,
    b'[a-z]+': OP_EXPECT_MORE_ALPHA,
    b'\d+': OP_EXPECT_MORE_DIGITS,
    b'[0-9]+': OP_EXPECT_MORE_DIGITS,
    b'[^/]+': OP_EXPECT_NOSLASH,
    b'[^-]+': OP_EXPECT_NODASH,
    b'.+': OP_EXPECT_ALL,
}

OPCODES_REV = {v: k for k, v in OPCODES.items()}


cdef class Edge:
    cdef public bytes pattern
    cdef public Node child
    cdef public unsigned int opcode

    def __cinit__(self, pattern, child):
        self.pattern = pattern
        self.child = child

    cdef branch_at(self, prefix):
        cdef:
            Node new_child = Node()
            bytes rest = self.pattern[len(prefix):]
        new_child.connect(self.child, rest)
        self.child = new_child
        self.pattern = self.pattern[:len(prefix)]

    cpdef bytes compile(self):
        cdef:
            unsigned int start = self.pattern.find(b'{')
            unsigned int end = self.pattern.find(b'}')
            bytes segment = self.pattern[start:end]
            list parts = segment.split(b':')
            bytes pattern
        if len(parts) == 2:
            pattern = parts[1]
        else:
            pattern = OPCODES_REV[OP_EXPECT_NOSLASH]
        if pattern in OPCODES:
            self.opcode = OPCODES[pattern]
        return pattern

    cdef bytes match(self, const char *path, list params):
        cdef:
            unsigned int i = 0
            unsigned int bound = len(self.pattern)
            unsigned int path_len = len(path)
            int start = self.pattern.find(b'{')
            int end = self.pattern.find(b'}')
            bytes rest
        # Placeholder is not at the start (eg. "foo.{ext}").
        if start > 0:
            if not self.pattern[:start] == path[:start]:
                return
        if self.opcode == OP_EXPECT_ALL:
            i = path_len
        elif self.opcode == OP_EXPECT_NOSLASH:
            for i in range(start, path_len):
                if path[i] == ord(b'/'):
                    break
            else:
                if i:
                    i = path_len
        elif self.opcode == OP_EXPECT_MORE_ALPHA:
            for i in range(start, path_len):
                if not chr(path[i]).isalpha():
                    break
            else:
                if i:
                    i = path_len
        elif self.opcode == OP_EXPECT_MORE_DIGITS:
            for i in range(start, path_len):
                if not chr(path[i]).isdigit():
                    break
            else:
                if i:
                    i = path_len
        elif self.opcode == OP_EXPECT_MORE_WORDS:
            for i in range(start, path_len):
                if not chr(path[i]).isdigit() and not chr(path[i]).isalpha():
                    break
            else:
                if i:
                    i = path_len
        elif self.opcode == OP_EXPECT_NODASH:
            for i in range(start, path_len):
                if path[i] == ord(b'-'):
                    break
            else:
                if i:
                    i = path_len
        if i:
            params.append(path[start:i])
            if end+1 < bound:
                # The placeholder is not at the end (eg. "{name}.json").
                rest = self.pattern[end+1:]
                if path[i:i+len(rest)] != rest:
                    return
                i += len(rest)
            return path[:i]


cdef class Route:
    cdef public bytes path
    cdef public list slugs
    cdef public object payload
    SLUGS = re.compile(b'{([^:}]+).*?}')

    def __cinit__(self, bytes path, object payload):
        self.path = path
        self.payload = payload
        self.slugs = Route.SLUGS.findall(path)


cdef class Node:
    cdef public object payload
    cdef public list edges
    cdef public list routes
    cdef public unsigned int compare_type # pcre, opcode, string
    cdef public unsigned int endpoint # should be zero for non-endpoint nodes
    cdef public object compiled
    cdef public bytes combined

    cdef void attach_route(self, const char *path, void *payload):
        if not self.routes:
            self.routes = []
        self.routes.append(Route(path, <object>payload))
        self.endpoint = 1

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
            unsigned int i, bound
            unsigned int path_len = len(path)
            unsigned int match_len
            bytes match, rest
            Edge edge

        if self.edges:
            # OP match.
            if self.compare_type == NODE_COMPARE_OPCODE:
                for edge in self.edges:
                    match = edge.match(path, params)
                    if match:
                        match_len = len(match)
                        if path_len == match_len and edge.child.endpoint:
                            return edge
                        return edge.child.match(path[match_len:], params)
            # Regex match.
            if self.compiled:
                matched = self.compiled.match(path)
                if matched:
                    params.append(matched.group(matched.lastindex))
                    edge = self.edges[matched.lastindex-1]
                    if matched.end() == path_len:
                        if edge.child.endpoint:
                            return edge
                    else:
                        return edge.child.match(path[matched.end():], params)
            # Simple match.
            for edge in self.edges:
                if path.startswith(edge.pattern) or edge.pattern.startswith(path):
                    if path_len == len(edge.pattern):
                        return edge
                    return edge.child.match(path[len(edge.pattern):], params)
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
                if edge.pattern.find(b'{') != -1:  # TODO validate {} pairs.
                    # compile "foo/{slug}" to "foo/[^/]+"
                    has_slug = True
                    pattern += edge.compile()
                    if edge.opcode:
                        count += 1
                else:
                    pattern += b'^(%b)' % edge.pattern
                if i+1 < total:
                    pattern += b'|'

            # if all edges use opcode, we should skip the combined_pattern.
            if count and count == total:
                self.compare_type = NODE_COMPARE_OPCODE
            elif has_slug:
                self.compare_type = NODE_COMPARE_PCRE
                self.combined = pattern
                self.compiled = re.compile(pattern)


cdef class Routes:

    cdef Node root

    def __cinit__(self):
        self.root = Node()

    def connect(self, bytes path, **payload):
        cdef Node node
        node = self.insert(self.root, path, <void*>payload)
        node.attach_route(path, <void*>payload)
        self.compile()

    def follow(self, bytes path):
        return self.match(self.root, path)

    cdef tuple match(self, Node node, bytes path):
        cdef:
            list values = []
            dict params = {}
            list slugs
            unsigned int i, n
        edge = node.match(path, values)
        if edge:
            # FIXME: more than 30% time lost in computing params.
            slugs = edge.child.routes[0].slugs
            n = len(slugs)
            for i in range(n):
                params[slugs[i]] = values[i]
            return edge.child.payload, params
        return None, None

    def dump(self):
        self._dump(self.root)

    cdef _dump(self, node, level=0):
        i = " " * level * 4
        print(f'{i}(o)')
        if node.compare_type:
            print(f'{i}| compare_type:%d' % node.compare_type)
        if node.combined:
            print(f'{i}| regexp: %s' % node.combined)
        # print(f'{i}| endpoint: %d' % node.endpoint)

        if node.payload:
            print(f'{i}| data: %s' % node.payload)

        if node.routes:
            print(f'{i}| routes (%d):' % len(node.routes));
            for route in node.routes:
                print(f'{i}    | path: %s' % route.path)
                print(f'{i}    | slugs: %s' % route.slugs)
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

    cdef Node insert(self, Node tree, const char *path, void *payload):
        cdef:
            Node node = tree
            # common edge
            Edge edge = None
            bytes prefix
            int bound, end, nb_slugs

        # If there is no path to insert at the node, we just increase the mount
        # point on the node and append the route.
        if not len(path):
            return tree

        # TODO: ignore slugs
        edge, prefix = node.common_prefix(path)

        if not edge:
            nb_slugs = path.count(b'{')
            bound = path.find(b'{')
            if nb_slugs > 1:
                # Break into parts
                child = Node()
                # if bound == 0:
                bound = path.find(b'{', bound + 1)  # Goto the next one.
                node.connect(child, path[:bound])
                return self.insert(child, path[bound:], payload)
            elif nb_slugs:
                # slug does not start at first char (eg. foo{slug})
                if bound > 0:
                    child = Node()
                    node.connect(child, path[:bound])
                else:
                    child = node
                leaf = Node()
                end = path.find(b'}')
                child.connect(leaf, path[bound:end+1])
                if len(path) > end+1:
                    return self.insert(leaf, path[end+1:], payload)
                leaf.payload = <object>payload
                return leaf
            else:
                child = Node()
                child.endpoint = 1
                child.payload = <object>payload
                edge = node.connect(child, path)
                return child
        elif len(prefix) == len(edge.pattern):
            if len(path) > len(prefix):
                return self.insert(edge.child, path[len(prefix):], payload)
            return edge.child
        elif len(prefix) < len(edge.pattern):
            edge.branch_at(prefix)
            return self.insert(edge.child, path[len(prefix):], payload)
