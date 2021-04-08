
import pytest
from autoroutes import InvalidRoute


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


def test_match_returns_params(routes):
    routes.add('/foo/{id}', data='x')
    assert routes.match('/foo/bar')[1] == {'id': 'bar'}


def test_match_returns_params_in_the_middle(routes):
    routes.add('/foo/{id}/bar', data='x')
    assert routes.match('/foo/22/bar') == ({'data': 'x'}, {'id': '22'})


def test_match_with_param_and_extension(routes):
    routes.add('/foo/{id}.html', data='x')
    assert routes.match('/foo/bar.html') == ({'data': 'x'}, {'id': 'bar'})


def test_match_with_alnum_param_and_extension(routes):
    routes.add('/foo/{id:alnum}.html', data='x')
    assert routes.match('/foo/bar22.html') == ({'data': 'x'}, {'id': 'bar22'})


def test_match_with_matchall_param_and_extension(routes):
    routes.add('/foo/{id:path}.html', data='x')
    assert routes.match('/foo/bar/2.html') == ({'data': 'x'}, {'id': 'bar/2'})


def test_add_can_handle_different_subpaths_after_placeholder(routes):
    routes.add('/foo/{id}/bar', data='x')
    routes.add('/foo/{id}/baz', data='y')
    assert routes.match('/foo/22/bar') == ({'data': 'x'}, {'id': '22'})
    assert routes.match('/foo/33/baz') == ({'data': 'y'}, {'id': '33'})


def test_add_param_regex_can_be_changed(routes):
    routes.add(r'/foo/{id:\d+}', something='x')
    assert routes.match('/foo/bar') == (None, None)
    assert routes.match('/foo/22') == ({'something': 'x'}, {'id': '22'})


def test_add_param_regex_can_consume_slash(routes):
    routes.add('/foo/{path:.+}', something='x')
    assert routes.match('/foo/path/to/somewhere') == \
        ({'something': 'x'}, {'path': 'path/to/somewhere'})


def test_param_regex_can_combine_with_flat_node(routes):
    routes.add('/foo/cache/{path:.*}', something='x')
    routes.add('/foo/{path:.*}', something='y')
    assert routes.match('/foo/cache/path/to/somewhere') == \
        ({'something': 'x'}, {'path': 'path/to/somewhere'})


def test_param_regex_wildcard_can_consume_empty_string(routes):
    routes.add('/foo/cache/{path:.*}', something='x')
    routes.add('/foo/{path:.*}', something='y')
    assert routes.match('/foo/cache/') == ({'something': 'x'}, {'path': ''})
    assert routes.match('/foo/') == ({'something': 'y'}, {'path': ''})


def test_add_param_regex_can_be_complex(routes):
    routes.add('/foo/{path:(some|any)where}', something='x')
    assert routes.match('/foo/somewhere')[1] == {'path': 'somewhere'}
    assert routes.match('/foo/anywhere')[1] == {'path': 'anywhere'}
    assert routes.match('/foo/nowhere')[1] is None


def test_add_with_clashing_regexes(routes):
    routes.add('/foo/{path:[abc]}', something='x')
    routes.add('/foo/{path:[xyz]}', something='y')
    assert routes.match('/foo/a') == ({'something': 'x'}, {'path': 'a'})
    assert routes.match('/foo/x') == ({'something': 'y'}, {'path': 'x'})


def test_add_with_regex_clashing_with_placeholder(routes):
    routes.add('/foo/{path:[abc]}', something='x')
    routes.add('/foo/{path:digit}', something='y')
    assert routes.match('/foo/a') == ({'something': 'x'}, {'path': 'a'})
    assert routes.match('/foo/12') == ({'something': 'y'}, {'path': '12'})


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


def test_one_char_with_leading_placeholder(routes):
    routes.add('/foo/path', something='x')
    routes.add('/foo/{id}', something='y')
    assert routes.match('/foo/i') == ({'something': 'y'}, {'id': 'i'})


def test_one_char_with_leading_digit_placeholder(routes):
    routes.add('/foo/path', something='x')
    routes.add('/foo/{id:digit}', something='y')
    assert routes.match('/foo/1') == ({'something': 'y'}, {'id': '1'})


def test_add_respesct_clashing_edges_registration_order(routes):
    routes.add('/foo/{id}/{sub}', something='y')
    routes.add('/foo/{id}/path', something='x')
    assert routes.match('/foo/id/path') == \
        ({'something': 'y'}, {'id': 'id', 'sub': 'path'})


def test_add_can_deal_with_clashing_vars_of_same_type(routes):
    routes.add('/foo/{category}/{id:digit}.csv', something='c')
    routes.add('/foo/{category}/{id:alnum}.txt', something='x')
    routes.add('/foo/{category}/{id:alnum}.json', something='j')
    assert routes.match('/foo/cat/id.txt') == (
        {'something': 'x'}, {'id': 'id', 'category': 'cat'})
    assert routes.match('/foo/cat/id.json') == (
        {'something': 'j'}, {'id': 'id', 'category': 'cat'})
    assert routes.match('/foo/cat/id.csv') == (None, None)
    assert routes.match('/foo/cat/123.csv') == (
        {'something': 'c'}, {'id': '123', 'category': 'cat'})


def test_add_deals_with_clashing_vars_of_same_type_and_different_names(routes):
    routes.add('/foo/{foo}/{id:digit}.csv', something='c')
    routes.add('/foo/{bar}/{id:alnum}.txt', something='x')
    routes.add('/foo/{baz}/{id:alnum}.json', something='j')
    assert routes.match('/foo/cat/id.txt') == (
        {'something': 'x'}, {'id': 'id', 'bar': 'cat'})
    assert routes.match('/foo/cat/id.json') == (
        {'something': 'j'}, {'id': 'id', 'baz': 'cat'})
    assert routes.match('/foo/cat/id.csv') == (None, None)
    assert routes.match('/foo/cat/123.csv') == (
        {'something': 'c'}, {'id': '123', 'foo': 'cat'})


def test_add_deals_with_multiple_clashing_vars(routes):
    routes.add('/{names}/{z:digit}/{x:digit}/{y:digit}.pbf', foo='pbf')
    routes.add('/{namespace}/{names}/{z:digit}/{x:digit}/{y:digit}.pbf',
               foo='npbf')
    routes.add('/{names}/{z:digit}/{x:digit}/{y:digit}.mvt', foo='mvt')
    routes.add('/{namespace}/{names}/{z:digit}/{x:digit}/{y:digit}.mvt',
               foo='nmvt')
    assert routes.match('/default/mylayer/0/0/0.pbf') == (
        {'foo': 'npbf'}, {'names': 'mylayer', 'namespace': 'default', 'x': '0',
                          'y': '0', 'z': '0'})
    assert routes.match('/default/mylayer/0/0/0.mvt') == (
        {'foo': 'nmvt'}, {'names': 'mylayer', 'namespace': 'default', 'x': '0',
                          'y': '0', 'z': '0'})
    assert routes.match('/mylayer/0/0/0.pbf') == (
        {'foo': 'pbf'}, {'names': 'mylayer', 'x': '0', 'y': '0', 'z': '0'})
    assert routes.match('/mylayer/0/0/0.mvt') == (
        {'foo': 'mvt'}, {'names': 'mylayer', 'x': '0', 'y': '0', 'z': '0'})


def test_match_long_placeholder_with_suffix(routes):
    routes.add('/{bar}/', something='x')
    assert routes.match('/sdlfkseirsldkfjsie/') == (
        {'something': 'x'}, {'bar': 'sdlfkseirsldkfjsie'})


def test_match_any(routes):
    routes.add('/foo/priority', something='z')
    routes.add('/foo/{bar:any}', something='x')
    assert routes.match('/foo/baz') == ({'something': 'x'}, {'bar': 'baz'})
    assert routes.match('/foo/') == ({'something': 'x'}, {'bar': ''})
    assert routes.match('/foo/priority') == ({'something': 'z'}, {})


def test_match_any_with_prefix_should_not_match_path_wihout_prefix(routes):
    routes.add("/foo/{path:any}", root="../foo/")
    routes.add("/{path:any}", root=".")
    assert routes.match("/") == ({"root": "."}, {"path":  ""})


def test_regex_combined_with_pattern_and_prefix(routes):
    routes.add("/foo/bar/{id}", data="a")
    routes.add(r"/foo/{id:[^\.]+}.html", data="b")
    assert routes.match("/foo/pouet.html") == ({"data": "b"}, {"id":  "pouet"})
    assert routes.match("/foo/bar/pouet") == ({"data": "a"}, {"id":  "pouet"})


def test_variables_without_slash_should_not_match_slash(routes):
    routes.add('root/{foo}', data="one")
    routes.add('root/foo/{bar}', data="two")
    assert routes.match('root/foo/123') == ({"data": "two"}, {"bar": "123"})
