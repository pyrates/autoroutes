
import pytest

from autoroutes import Routes


@pytest.fixture
def routes():
    routes_ = Routes()
    yield routes_
    routes_.dump()  # Will display only in case of failure.
    del routes_


def test_simple_follow(routes):
    routes.connect(b'/foo', something='x')
    assert routes.follow(b'/foo') == ({'something': 'x'}, {})


def test_follow_root(routes):
    routes.connect(b'/', something='x')
    assert routes.follow(b'/') == ({'something': 'x'}, {})


def test_follow_unicode_routes(routes):
    path = '/éèà'.encode(encoding='utf-8')
    routes.connect(path, something='àô')
    assert routes.follow(path) == ({'something': 'àô'}, {})


def test_follow_unknown_path(routes):
    routes.connect(b'/foo/', data='x')
    assert routes.follow(b'/bar/') == (None, None)


def test_follow_unknown_path_with_param(routes):
    routes.connect(b'/foo/{id}', data='x')
    assert routes.follow(b'/bar/foo') == (None, None)


def test_follow_return_params(routes):
    routes.connect(b'/foo/{id}', data='x')
    assert routes.follow(b'/foo/bar')[1] == {b'id': b'bar'}
    assert routes.follow('/foo/bar'.encode())[1] == {b'id': b'bar'}


def test_follow_return_params_in_the_middle(routes):
    routes.connect(b'/foo/{id}/bar', data='x')
    assert routes.follow(b'/foo/22/bar') == ({'data': 'x'}, {b'id': b'22'})


def test_follow_can_handle_different_subpaths_after_placeholder(routes):
    routes.connect(b'/foo/{id}/bar', data='x')
    routes.connect(b'/foo/{id}/baz', data='y')
    assert routes.follow(b'/foo/22/bar') == ({'data': 'x'}, {b'id': b'22'})
    assert routes.follow(b'/foo/33/baz') == ({'data': 'y'}, {b'id': b'33'})


def test_follow_param_regex_can_be_changed(routes):
    routes.connect(b'/foo/{id:\d+}', something='x')
    assert routes.follow(b'/foo/bar') == (None, None)
    assert routes.follow(b'/foo/22') == ({'something': 'x'}, {b'id': b'22'})


def test_follow_param_regex_can_consume_slash(routes):
    routes.connect(b'/foo/{path:.+}', something='x')
    assert routes.follow(b'/foo/path/to/somewhere') == \
        ({'something': 'x'}, {b'path': b'path/to/somewhere'})


def test_follow_segment_can_mix_string_and_param(routes):
    routes.connect(b'/foo.{ext}', data='x')
    assert routes.follow(b'/foo.json')[1] == {b'ext': b'json'}
    assert routes.follow(b'/foo.txt')[1] == {b'ext': b'txt'}


def test_connect_can_be_overriden(routes):
    routes.connect(b'/foo/', data='old')
    routes.connect(b'/foo/', data='new')
    assert routes.follow(b'/foo/') == ({'data': 'new'}, {})


def test_follow_accept_func_as_data(routes):

    def handler():
        pass

    routes.connect(b'/foo', handler=handler)
    assert routes.follow(b'/foo') == ({'handler': handler}, {})


def test_follow_accepts_multiple_params(routes):
    routes.connect(b'/foo/{id}/bar/{sub}', something='x')
    assert routes.follow(b'/foo/id/bar/sub') == \
        ({'something': 'x'}, {b'id': b'id', b'sub': b'sub'})


def test_follow_accepts_multiple_params_in_succession(routes):
    routes.connect(b'/foo/{id}/{sub}', something='x')
    assert routes.follow(b'/foo/id/sub') == \
        ({'something': 'x'}, {b'id': b'id', b'sub': b'sub'})


def test_follow_can_deal_with_conflicting_edges(routes):
    routes.connect(b'/foo/{id}/path', something='x')
    routes.connect(b'/foo/{id}/{sub}', something='y')
    assert routes.follow(b'/foo/id/path') == \
        ({'something': 'x'}, {b'id': b'id'})
