import pytest

from autoroutes import Edge, Node


@pytest.mark.parametrize('pattern,expected', [
    ['{id}', 'string'],
    ['{id:digit}', 'digit'],
    ['{id:\d+}', '\d+'],
    ['{id:[abc]}', '[abc]'],
    ['{id:.+}', '.+'],
])
def test_edge_compile(pattern, expected):
    assert Edge(pattern, Node()).compile() == expected
