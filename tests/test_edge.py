import pytest
from autoroutes import Edge, Node


@pytest.mark.parametrize('pattern,expected', [
    ['{id}', '^([^/]+)'],
    ['{id:string}', '^([^/]+)'],
    ['{id:digit}', r'^(\d+)'],
    [r'{id:\d+}', r'^(\d+)'],
    ['{id:[abc]}', '^([abc])'],
    ['{id:.+}', '^(.+)'],
    ['bar/{id}', '^bar/([^/]+)'],
])
def test_edge_compile(pattern, expected):
    edge = Edge(pattern, Node())
    edge.compile()
    assert edge.regex == expected


def test_edge_insert_same_path(routes):
    routes.add('/foo', x='1')
    root = routes.root
    assert len(root.edges) == 1
    routes.add('/foo', y='2')
    assert len(root.edges) == 1
    assert root.edges[0].child.payload == {'x': '1', 'y': '2'}


def test_edge_insert_prefix_vs_placeholder(routes):
    routes.add('foo', x='1')
    root = routes.root
    assert len(root.edges) == 1
    routes.add('{foo}', x='2')
    assert len(root.edges) == 2
    assert root.edges[0].child.payload == {'x': '1'}
    assert root.edges[1].child.payload == {'x': '2'}


def test_edge_join_longer_path(routes):
    routes.add('/foo', x='1')
    root = routes.root
    assert len(root.edges) == 1
    assert not root.edges[0].child.edges
    routes.add('/foo/bar', x='2')
    leaf = root.edges[0].child
    assert leaf.payload == {'x': '1'}
    assert root.edges[0].pattern == '/foo'
    leaf = root.edges[0].child.edges[0].child
    assert leaf.payload == {'x': '2'}
    assert root.edges[0].child.edges[0].pattern == '/bar'


def test_edge_join_shorter_path(routes):
    routes.add('/foo/bar', x='1')
    root = routes.root
    assert len(root.edges) == 1
    assert root.edges[0].pattern == '/foo/bar'
    routes.add('/foo', x='2')
    assert len(root.edges) == 1
    leaf = root.edges[0].child
    assert leaf.payload == {'x': '2'}
    assert root.edges[0].pattern == '/foo'
    assert len(root.edges[0].child.edges) == 1
    leaf = root.edges[0].child.edges[0].child
    assert leaf.payload == {'x': '1'}
    assert root.edges[0].child.edges[0].pattern == '/bar'


def test_edge_join_same_root(routes):
    routes.add('/foo/bar', x='1')
    root = routes.root
    assert len(root.edges) == 1
    assert root.edges[0].pattern == '/foo/bar'
    routes.add('/foo/baz', x='2')
    assert len(root.edges) == 1
    assert not root.edges[0].child.payload
    assert root.edges[0].pattern == '/foo/ba'
    assert len(root.edges[0].child.edges) == 2
    leaf = root.edges[0].child.edges[0].child
    assert leaf.payload == {'x': '1'}
    assert root.edges[0].child.edges[0].pattern == 'r'
    leaf = root.edges[0].child.edges[1].child
    assert leaf.payload == {'x': '2'}
    assert root.edges[0].child.edges[1].pattern == 'z'


def test_edge_insert_same_path_and_placeholder(routes):
    routes.add('/foo/{bar}', x='1')
    root = routes.root
    assert len(root.edges) == 1
    routes.add('/foo/{bar}', y='2')
    assert len(root.edges) == 1
    assert root.edges[0].child.payload == {'x': '1', 'y': '2'}


def test_edge_insert_same_path_and_placeholder_type(routes):
    routes.add('/foo/{bar:digit}', x='1')
    root = routes.root
    assert len(root.edges) == 1
    routes.add('/foo/{bar:digit}', y='2')
    assert len(root.edges) == 1
    assert root.edges[0].child.payload == {'x': '1', 'y': '2'}


def test_edge_insert_same_path_and_placeholder_type_w_different_name(routes):
    routes.add('/foo/{bar:digit}', x='1')
    root = routes.root
    assert len(root.edges) == 1
    routes.add('/foo/{baz:digit}', y='2')
    assert len(root.edges) == 1
    assert root.edges[0].child.payload == {'x': '1', 'y': '2'}


def test_edge_insert_same_prefix_and_different_placeholder(routes):
    routes.add('/foo/{bar:digit}', x='1')
    root = routes.root
    assert len(root.edges) == 1
    routes.add('/foo/{bar:string}', x='2')
    assert len(root.edges) == 1
    assert root.edges[0].pattern == '/foo/'
    assert len(root.edges[0].child.edges) == 2
    assert root.edges[0].child.edges[0].pattern == '{bar:digit}'
    assert root.edges[0].child.edges[0].child.payload == {'x': '1'}
    assert root.edges[0].child.edges[1].pattern == '{bar:string}'
    assert root.edges[0].child.edges[1].child.payload == {'x': '2'}


def test_edge_insert_same_prefix_and_different_placeholder_and_suffix(routes):
    routes.add('/foo/{bar:digit}/baz', x='1')
    root = routes.root
    assert len(root.edges) == 1
    routes.add('/foo/{bar:string}/baz', x='2')
    assert len(root.edges) == 1
    assert root.edges[0].pattern == '/foo/'
    assert len(root.edges[0].child.edges) == 2
    assert root.edges[0].child.edges[0].pattern == '{bar:digit}/baz'
    assert root.edges[0].child.edges[0].child.payload == {'x': '1'}
    assert root.edges[0].child.edges[1].pattern == '{bar:string}/baz'
    assert root.edges[0].child.edges[1].child.payload == {'x': '2'}


def test_edge_join_longer_prefix_with_local_placeholder(routes):
    routes.add('/foo/{bar}', x='1')
    root = routes.root
    assert len(root.edges) == 1
    assert not root.edges[0].child.edges
    routes.add('/foo/baz', x='2')
    assert root.edges[0].pattern == '/foo/'
    assert not root.edges[0].child.payload
    leaf = root.edges[0].child.edges[0].child
    assert leaf.payload == {'x': '1'}
    assert root.edges[0].child.edges[0].pattern == '{bar}'
    leaf = root.edges[0].child.edges[1].child
    assert leaf.payload == {'x': '2'}
    assert root.edges[0].child.edges[1].pattern == 'baz'


def test_edge_join_longer_prefix_with_local_placeholder2(routes):
    routes.add('/foo/baz/{bar}', x='1')
    root = routes.root
    assert len(root.edges) == 1
    assert not root.edges[0].child.edges
    routes.add('/foo/bar', x='2')
    assert root.edges[0].pattern == '/foo/ba'
    assert not root.edges[0].child.payload
    leaf = root.edges[0].child.edges[0].child
    assert leaf.payload == {'x': '1'}
    assert root.edges[0].child.edges[0].pattern == 'z/{bar}'
    leaf = root.edges[0].child.edges[1].child
    assert leaf.payload == {'x': '2'}
    assert root.edges[0].child.edges[1].pattern == 'r'


def test_edge_join_longer_prefix_with_remote_placeholder(routes):
    routes.add('/foo/baz', x='1')
    root = routes.root
    assert len(root.edges) == 1
    assert not root.edges[0].child.edges
    routes.add('/foo/{bar}', x='2')
    assert root.edges[0].pattern == '/foo/'
    assert not root.edges[0].child.payload
    leaf = root.edges[0].child.edges[0].child
    assert leaf.payload == {'x': '1'}
    assert root.edges[0].child.edges[0].pattern == 'baz'
    leaf = root.edges[0].child.edges[1].child
    assert leaf.payload == {'x': '2'}
    assert root.edges[0].child.edges[1].pattern == '{bar}'


def test_edge_join_longer_prefix_with_remote_placeholder2(routes):
    routes.add('/foo/bar', x='1')
    root = routes.root
    assert len(root.edges) == 1
    assert not root.edges[0].child.edges
    routes.add('/foo/baz/{bar}', x='2')
    assert root.edges[0].pattern == '/foo/ba'
    assert not root.edges[0].child.payload
    leaf = root.edges[0].child.edges[0].child
    assert leaf.payload == {'x': '1'}
    assert root.edges[0].child.edges[0].pattern == 'r'
    leaf = root.edges[0].child.edges[1].child
    assert leaf.payload == {'x': '2'}
    assert root.edges[0].child.edges[1].pattern == 'z/{bar}'


def test_edge_insert_same_path_placeholder_and_suffix(routes):
    routes.add('/foo/{bar}/baz', x='1')
    root = routes.root
    assert len(root.edges) == 1
    routes.add('/foo/{bar}/baz', y='2')
    assert len(root.edges) == 1
    assert root.edges[0].child.payload == {'x': '1', 'y': '2'}


def test_edge_join_longer_suffix(routes):
    routes.add('/foo/{bar}/', x='1')
    root = routes.root
    assert len(root.edges) == 1
    assert not root.edges[0].child.edges
    routes.add('/foo/{bar}/baz', x='2')
    leaf = root.edges[0].child
    assert leaf.payload == {'x': '1'}
    assert root.edges[0].pattern == '/foo/{bar}/'
    leaf = root.edges[0].child.edges[0].child
    assert leaf.payload == {'x': '2'}
    assert root.edges[0].child.edges[0].pattern == 'baz'


def test_edge_join_shorter_suffix(routes):
    routes.add('/foo/{bar}/baz', x='1')
    root = routes.root
    assert len(root.edges) == 1
    assert root.edges[0].pattern == '/foo/{bar}/baz'
    routes.add('/foo/{bar}/', x='2')
    assert root.edges[0].pattern == '/foo/{bar}/'
    assert len(root.edges) == 1
    leaf = root.edges[0].child
    assert leaf.payload == {'x': '2'}
    assert root.edges[0].pattern == '/foo/{bar}/'
    assert len(root.edges[0].child.edges) == 1
    leaf = root.edges[0].child.edges[0].child
    assert leaf.payload == {'x': '1'}
    assert root.edges[0].child.edges[0].pattern == 'baz'


def test_edge_join_same_suffix_root(routes):
    routes.add('/foo/{bar}/bar', x='1')
    root = routes.root
    assert len(root.edges) == 1
    assert root.edges[0].pattern == '/foo/{bar}/bar'
    routes.add('/foo/{bar}/baz', x='2')
    assert len(root.edges) == 1
    assert not root.edges[0].child.payload
    assert root.edges[0].pattern == '/foo/{bar}/ba'
    assert len(root.edges[0].child.edges) == 2
    leaf = root.edges[0].child.edges[0].child
    assert leaf.payload == {'x': '1'}
    assert root.edges[0].child.edges[0].pattern == 'r'
    leaf = root.edges[0].child.edges[1].child
    assert leaf.payload == {'x': '2'}
    assert root.edges[0].child.edges[1].pattern == 'z'


def test_edge_insert_same_placeholder_and_suffix(routes):
    routes.add('{bar}/foo', x='1')
    root = routes.root
    assert len(root.edges) == 1
    routes.add('{bar}/foo', y='2')
    assert len(root.edges) == 1
    assert root.edges[0].child.payload == {'x': '1', 'y': '2'}


def test_edge_insert_same_placeholder_with_different_suffix(routes):
    routes.add('{bar}/foo', x='1')
    root = routes.root
    assert len(root.edges) == 1
    assert root.edges[0].child.payload == {'x': '1'}
    routes.add('{bar}/bar', y='2')
    assert len(root.edges) == 1
    assert not root.edges[0].child.payload
    assert len(root.edges[0].child.edges) == 2
    assert root.edges[0].child.edges[0].child.payload == {'x': '1'}
    assert root.edges[0].child.edges[1].child.payload == {'y': '2'}


def test_edge_insert_same_placeholder_with_one_suffix(routes):
    routes.add('{bar}', x='1')
    root = routes.root
    assert len(root.edges) == 1
    assert root.edges[0].child.payload == {'x': '1'}
    routes.add('{bar}/bar', y='2')
    assert len(root.edges) == 1
    assert root.edges[0].child.payload == {'x': '1'}
    assert len(root.edges[0].child.edges) == 1
    assert root.edges[0].child.edges[0].child.payload == {'y': '2'}
