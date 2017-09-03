from cpython cimport array
import array
import re


class NoRoute(Exception):
    ...

cdef enum:
    NODE_COMPARE_STR, NODE_COMPARE_PCRE, NODE_COMPARE_OPCODE
    OP_EXPECT_MORE_DIGITS = 1, OP_EXPECT_MORE_WORDS, OP_EXPECT_NOSLASH, OP_EXPECT_NODASH, OP_EXPECT_MORE_ALPHA


OPCODES = {
    b'\w+': OP_EXPECT_MORE_WORDS,
    b'[0-9a-z]+': OP_EXPECT_MORE_WORDS,
    b'[a-z0-9]+': OP_EXPECT_MORE_WORDS,
    b'[a-z]+': OP_EXPECT_MORE_ALPHA,
    b'\d+': OP_EXPECT_MORE_DIGITS,
    b'[0-9]+': OP_EXPECT_MORE_DIGITS,
    b'[^/]+': OP_EXPECT_NOSLASH,
    b'[^-]+': OP_EXPECT_NODASH,
}

OPCODES_REV = {v: k for k, v in OPCODES.items()}


cdef class Edge:
    cdef public bytes pattern
    cdef public Node child
    cdef public unsigned int opcode
    # unsigned int has_slug

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

    cdef bytes compile(self):
        cdef:
            unsigned int start = self.pattern.find(b'{')
            unsigned int end = self.pattern.find(b'}')
            bytes segment = self.pattern[start:end+1]
            list parts = segment.split(b':')
            bytes pattern
        if len(parts) == 2:
            pattern = parts[1]
        else:
            pattern = OPCODES_REV[OP_EXPECT_NOSLASH]
        return pattern

    cdef unsigned int match(self, const char *path):
        cdef:
            unsigned int i = 0
            unsigned int n = len(path)
        if self.opcode == OP_EXPECT_NOSLASH:
            for i in range(n):
                if path[i] == ord(b'/'):
                    return i
            else:
                if i:
                    return n
        elif self.opcode == OP_EXPECT_MORE_ALPHA:
            for i in range(n):
                if not chr(path[i]).isalpha():
                    return i
            else:
                if i:
                    return n
        elif self.opcode == OP_EXPECT_MORE_DIGITS:
            for i in range(n):
                if not chr(path[i]).isdigit():
                    return i
            else:
                if i:
                    return n
        elif self.opcode == OP_EXPECT_MORE_WORDS:
            for i in range(n):
                if not chr(path[i]).isdigit() and not chr(path[i]).isalpha():
                    return i
            else:
                if i:
                    return n
        elif self.opcode == OP_EXPECT_NODASH:
            for i in range(n):
                if path[i] == ord(b'-'):
                    return i
            else:
                if i:
                    return n


cdef class Route:
    cdef public bytes path
    cdef list slugs
    cdef public object payload

    def __cinit__(self, path, payload):
        self.path = path
        self.payload = <object>payload


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
                        break
                else:
                    i = bound
                if i:
                    return edge, path[:i]
        return None, None

    cdef Edge match(self, const char *path):
        cdef:
            unsigned int i, bound, matched
            unsigned int path_len = len(path)
            Edge edge

        if self.edges:
            # OP match.
            if self.compare_type == NODE_COMPARE_OPCODE:
                for edge in self.edges:
                    matched = edge.match(path)
                    if matched:
                        # TODO params
                        if len(path) == matched and edge.child.endpoint:
                            return edge
                        return edge.child.match(path[matched:])
            # Simple match.
            for edge in self.edges:
                if path.startswith(edge.pattern) or edge.pattern.startswith(path):
                    if len(path) == len(edge.pattern):
                        return edge
                    return edge.child.match(path[len(edge.pattern):])
        return None


    cdef void compile(self):
        cdef:
            unsigned int count = 0
            bytes pattern = b''
            unsigned int total = 0
            Edge edge
        if self.edges:
            total = len(self.edges)
            for i, edge in enumerate(self.edges):
                if edge.opcode:
                    count += 1
                if edge.pattern.find(b'{') != -1:  # TODO validate {} pairs.
                    # compile "foo/{slug}" to "foo/[^/]+"
                    pattern += edge.compile()
                else:
                    pattern += b'^(%b)' % edge.pattern
                if i+1 < total:
                    pattern += b'|'

            # if all edges use opcode, we should skip the combined_pattern.
            if count and count == total:
                self.compare_type = NODE_COMPARE_OPCODE
            else:
                self.compare_type = NODE_COMPARE_PCRE
            self.combined = pattern
            self.compiled = re.compile(pattern)


cdef class Routes:

    cdef Node root

    def __cinit__(self):
        self.root = Node()

    def connect(self, bytes path, **payload):
        self.insert(self.root, path, <void*>payload)
        self.compile()

    def follow(self, bytes path):
        return self.match(self.root, path)

    cdef Node match(self, Node node, bytes path):
        edge = node.match(path)
        if edge:
            return edge.child
        return None

    def dump(self):
        self._dump(self.root)

    cdef _dump(self, node, level=0):
        i = " " * level * 4
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
        if node.edges:
            for edge in node.edges:
                print(f'{i}' + '|--- %s' % edge.pattern)
                if edge.opcode:
                    print(f'{i}| opcode: %d' % edge.opcode)
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


        # If there is no path to insert at the node, we just increase the mount
        # point on the node and append the route.
        if not len(path):
            tree.endpoint = 1
            tree.attach_route(path, payload)
            return tree

        # TODO: ignore slugs
        edge, prefix = node.common_prefix(path)

        if not edge:
            nb_slugs = path.count(b'{')
            bound = path.find(b'{')
            if nb_slugs > 1:
                # Break into parts
                child = Node()
                node.connect(child, path[:bound])
                return self.insert(child, path[bound:], payload)
            elif nb_slugs:
                # slug does not starts at first char (eg. foo{slug})
                if bound > 0:
                    child = Node()
                    node.connect(child, path[:bound])
                else:
                    child = node
                leaf = Node()
                end = path.find(b'}')
                edge = child.connect(leaf, path[bound:end+1])
                pattern = edge.compile()
                if pattern in OPCODES:
                    edge.opcode = OPCODES[pattern]
                if len(path) > end:
                    return self.insert(leaf, path[end+1:], payload)
                leaf.payload = <object>payload
                leaf.endpoint = 1
                leaf.attach_route(path, payload)
                return leaf
            else:
                child = Node()
                child.endpoint = 1
                child.payload = <object>payload
                edge = node.connect(child, path)
                child.attach_route(path, payload)
                return child
        elif len(prefix) == len(edge.pattern):
            if len(path) > len(prefix):
                return self.insert(edge.child, path[len(prefix):], payload)
            edge.child.attach_route(path, payload)
            edge.child.endpoint = 1
            return edge.child
        elif len(prefix) < len(edge.pattern):
            edge.branch_at(prefix)
            return self.insert(edge.child, path[len(prefix):], payload)
