
import pytest

from autoroutes import Routes, InvalidRoute


@pytest.fixture
def routes():
    routes_ = Routes()
    yield routes_
    routes_.dump()  # Will display only in case of failure.
    del routes_


def test_simple_follow(routes):
    routes.add('/foo', something='x')
    assert routes.match('/foo') == ({'something': 'x'}, {})


def test_add_root(routes):
    routes.add('/', something='x')
    assert routes.match('/') == ({'something': 'x'}, {})


def test_add_unicode_routes(routes):
    routes.add('/éèà', something='àô')
    assert routes.match('/éèà') == ({'something': 'àô'}, {})


def test_add_unknown_path(routes):
    routes.add('/foo/', data='x')
    assert routes.match('/bar/') == (None, None)


def test_add_unknown_path_with_param(routes):
    routes.add('/foo/{id}', data='x')
    assert routes.match('/bar/foo') == (None, None)


def test_add_return_params(routes):
    routes.add('/foo/{id}', data='x')
    assert routes.match('/foo/bar')[1] == {'id': 'bar'}


def test_add_return_params_in_the_middle(routes):
    routes.add('/foo/{id}/bar', data='x')
    assert routes.match('/foo/22/bar') == ({'data': 'x'}, {'id': '22'})


def test_add_can_handle_different_subpaths_after_placeholder(routes):
    routes.add('/foo/{id}/bar', data='x')
    routes.add('/foo/{id}/baz', data='y')
    assert routes.match('/foo/22/bar') == ({'data': 'x'}, {'id': '22'})
    assert routes.match('/foo/33/baz') == ({'data': 'y'}, {'id': '33'})


def test_add_param_regex_can_be_changed(routes):
    routes.add('/foo/{id:\d+}', something='x')
    assert routes.match('/foo/bar') == (None, None)
    assert routes.match('/foo/22') == ({'something': 'x'}, {'id': '22'})


def test_add_param_regex_can_consume_slash(routes):
    routes.add('/foo/{path:.+}', something='x')
    assert routes.match('/foo/path/to/somewhere') == \
        ({'something': 'x'}, {'path': 'path/to/somewhere'})


def test_add_param_regex_can_be_complex(routes):
    routes.add('/foo/{path:(some|any)where}', something='x')
    assert routes.match('/foo/somewhere')[1] == {'path': 'somewhere'}
    assert routes.match('/foo/anywhere')[1] == {'path': 'anywhere'}
    assert routes.match('/foo/nowhere')[1] is None


def test_add_can_use_shortcut_types(routes):
    routes.add('/foo/{id:digit}/path', something='x')
    assert routes.match('/foo/123/path')[1] == {'id': '123'}
    assert routes.match('/foo/abc/path')[1] is None


def test_variable_type_word(routes):
    routes.add('/foo/{name:alnum}', something='x')
    assert routes.match('/foo/abc')[1] == {'name': 'abc'}
    assert routes.match('/foo/a.')[1] is None


def test_variable_type_word_accept_non_ascii_chars(routes):
    routes.add('/foo/{name:alnum}', something='x')
    assert routes.match('/foo/àéè')[1] == {'name': 'àéè'}
    assert routes.match('/foo/à.è')[1] is None


def test_variable_type_is_alpha(routes):
    routes.add('/foo/{name:alpha}', something='x')
    assert routes.match('/foo/abc')[1] == {'name': 'abc'}
    assert routes.match('/foo/a.')[1] is None
    assert routes.match('/foo/a2')[1] is None


def test_add_segment_can_mix_string_and_param(routes):
    routes.add('/foo.{ext}', data='x')
    assert routes.match('/foo.json')[1] == {'ext': 'json'}
    assert routes.match('/foo.txt')[1] == {'ext': 'txt'}


def test_add_with_clashing_placeholders_of_different_types(routes):
    routes.add('horse/{id:digit}/subpath', data='x')
    routes.add('horse/{id}/other', data='y')
    assert routes.match('horse/22/subpath') == ({'data': 'x'}, {'id': '22'})


def test_invalid_placeholder(routes):
    with pytest.raises(InvalidRoute):
        routes.add('/foo/{ext/', data='x')


def test_connect_can_be_updated(routes):
    routes.add('/foo/', data='old')
    routes.add('/foo/', data='new', other='new')
    assert routes.match('/foo/') == ({'data': 'new', 'other': 'new'}, {})


def test_add_accept_func_as_data(routes):

    def handler():
        pass

    routes.add('/foo', handler=handler)
    assert routes.match('/foo') == ({'handler': handler}, {})


def test_add_accepts_multiple_params(routes):
    routes.add('/foo/{id}/bar/{sub}', something='x')
    assert routes.match('/foo/id/bar/su') == \
        ({'something': 'x'}, {'id': 'id', 'sub': 'su'})


def test_add_accepts_multiple_params_in_succession(routes):
    routes.add('/foo/{id}/{sub}', something='x')
    assert routes.match('/foo/id/su') == \
        ({'something': 'x'}, {'id': 'id', 'sub': 'su'})


def test_add_can_deal_with_clashing_edges(routes):
    routes.add('/foo/{id}/path', something='x')
    routes.add('/foo/{id}/{sub}', something='y')
    assert routes.match('/foo/id/path') == ({'something': 'x'}, {'id': 'id'})


def test_add_respesct_clashing_edges_registration_order(routes):
    routes.add('/foo/{id}/{sub}', something='y')
    routes.add('/foo/{id}/path', something='x')
    assert routes.match('/foo/id/path') == \
        ({'something': 'y'}, {'id': 'id', 'sub': 'path'})
