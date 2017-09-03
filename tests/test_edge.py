import pytest

from autoroutes import Edge, Node


@pytest.mark.parametrize('pattern,expected', [
    [b'{id}', b'[^/]+'],
    [b'{id:\d+}', b'\d+'],
    [b'{id:[abc]}', b'[abc]'],
    [b'{id:.+}', b'.+'],
])
def test_edge_compile(pattern, expected):
    assert Edge(pattern, Node()).compile() == expected
