
import pytest

from autoroutes import Routes, InvalidRoute


@pytest.fixture
def routes():
    routes_ = Routes()
    yield routes_
    routes_.dump()  # Will display only in case of failure.
    del routes_


def test_simple_follow(routes):
    routes.connect('/foo', something='x')
    assert routes.follow('/foo') == ({'something': 'x'}, {})


def test_follow_root(routes):
    routes.connect('/', something='x')
    assert routes.follow('/') == ({'something': 'x'}, {})


def test_follow_unicode_routes(routes):
    routes.connect('/éèà', something='àô')
    assert routes.follow('/éèà') == ({'something': 'àô'}, {})


def test_follow_unknown_path(routes):
    routes.connect('/foo/', data='x')
    assert routes.follow('/bar/') == (None, None)


def test_follow_unknown_path_with_param(routes):
    routes.connect('/foo/{id}', data='x')
    assert routes.follow('/bar/foo') == (None, None)


def test_follow_return_params(routes):
    routes.connect('/foo/{id}', data='x')
    assert routes.follow('/foo/bar')[1] == {'id': 'bar'}


def test_follow_return_params_in_the_middle(routes):
    routes.connect('/foo/{id}/bar', data='x')
    assert routes.follow('/foo/22/bar') == ({'data': 'x'}, {'id': '22'})


def test_follow_can_handle_different_subpaths_after_placeholder(routes):
    routes.connect('/foo/{id}/bar', data='x')
    routes.connect('/foo/{id}/baz', data='y')
    assert routes.follow('/foo/22/bar') == ({'data': 'x'}, {'id': '22'})
    assert routes.follow('/foo/33/baz') == ({'data': 'y'}, {'id': '33'})


def test_follow_param_regex_can_be_changed(routes):
    routes.connect('/foo/{id:\d+}', something='x')
    assert routes.follow('/foo/bar') == (None, None)
    assert routes.follow('/foo/22') == ({'something': 'x'}, {'id': '22'})


def test_follow_param_regex_can_consume_slash(routes):
    routes.connect('/foo/{path:.+}', something='x')
    assert routes.follow('/foo/path/to/somewhere') == \
        ({'something': 'x'}, {'path': 'path/to/somewhere'})


def test_follow_param_regex_can_be_complex(routes):
    routes.connect('/foo/{path:(some|any)where}', something='x')
    assert routes.follow('/foo/somewhere')[1] == {'path': 'somewhere'}
    assert routes.follow('/foo/anywhere')[1] == {'path': 'anywhere'}
    assert routes.follow('/foo/nowhere')[1] is None


def test_follow_can_use_shortcut_types(routes):
    routes.connect('/foo/{id:i}/path', something='x')
    assert routes.follow('/foo/123/path')[1] == {'id': '123'}
    assert routes.follow('/foo/abc/path')[1] is None


def test_variable_type_no_dash(routes):
    routes.connect('/foo/{name:[^-]+}', something='x')
    assert routes.follow('/foo/abc')[1] == {'name': 'abc'}
    assert routes.follow('/foo/a-b-c')[1] is None


def test_variable_type_word(routes):
    routes.connect('/foo/{name:w}', something='x')
    assert routes.follow('/foo/abc')[1] == {'name': 'abc'}
    assert routes.follow('/foo/a.')[1] is None


def test_variable_type_word_accept_non_ascii_chars(routes):
    routes.connect('/foo/{name:word}', something='x')
    assert routes.follow('/foo/àéè')[1] == {'name': 'àéè'}
    assert routes.follow('/foo/à.è')[1] is None


def test_variable_type_is_alpha(routes):
    routes.connect('/foo/{name:[a-z]+}', something='x')
    assert routes.follow('/foo/abc')[1] == {'name': 'abc'}
    assert routes.follow('/foo/a.')[1] is None
    assert routes.follow('/foo/a2')[1] is None


def test_follow_segment_can_mix_string_and_param(routes):
    routes.connect('/foo.{ext}', data='x')
    assert routes.follow('/foo.json')[1] == {'ext': 'json'}
    assert routes.follow('/foo.txt')[1] == {'ext': 'txt'}


def test_follow_with_clashing_placeholders_of_different_types(routes):
    routes.connect('horse/{id:i}/subpath', data='x')
    routes.connect('horse/{id}/other', data='y')
    assert routes.follow('horse/22/subpath') == ({'data': 'x'}, {'id': '22'})


def test_invalid_placeholder(routes):
    with pytest.raises(InvalidRoute):
        routes.connect('/foo/{ext/', data='x')


def test_connect_can_be_overriden(routes):
    routes.connect('/foo/', data='old')
    routes.connect('/foo/', data='new')
    assert routes.follow('/foo/') == ({'data': 'new'}, {})


def test_follow_accept_func_as_data(routes):

    def handler():
        pass

    routes.connect('/foo', handler=handler)
    assert routes.follow('/foo') == ({'handler': handler}, {})


def test_follow_accepts_multiple_params(routes):
    routes.connect('/foo/{id}/bar/{sub}', something='x')
    assert routes.follow('/foo/id/bar/su') == \
        ({'something': 'x'}, {'id': 'id', 'sub': 'su'})


def test_follow_accepts_multiple_params_in_succession(routes):
    routes.connect('/foo/{id}/{sub}', something='x')
    assert routes.follow('/foo/id/su') == \
        ({'something': 'x'}, {'id': 'id', 'sub': 'su'})


def test_follow_can_deal_with_clashing_edges(routes):
    routes.connect('/foo/{id}/path', something='x')
    routes.connect('/foo/{id}/{sub}', something='y')
    assert routes.follow('/foo/id/path') == \
        ({'something': 'x'}, {'id': 'id'})


def test_follow_respesct_clashing_edges_registration_order(routes):
    routes.connect('/foo/{id}/{sub}', something='y')
    routes.connect('/foo/{id}/path', something='x')
    assert routes.follow('/foo/id/path') == \
        ({'something': 'y'}, {'id': 'id', 'sub': 'path'})
