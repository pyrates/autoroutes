from timeit import timeit
from autoroutes import Routes
import faulthandler
faulthandler.enable()

PATHS = ['/user/', '/user/{id}', '/user/{id}/subpath', '/user/{id}/subpath2',
         '/boat/', '/boat/{id}', '/boat/{id}/subpath', '/boat/{id}/subpath2',
         '/horse/', '/horse/{id}', '/horse/{id}/subpath',
         '/horse/{id}/subpath2', '/bicycle/', '/bicycle/{id}',
         '/bicycle/{id}/subpath2', '/bicycle/{id}/subpath']

routes = Routes()
for path in PATHS:
    routes.connect(path.encode(), GET='pouet')
# routes.connect(path=b'/horse/22/subpath', GET='pouet')
# routes.connect(path=b'/horse/{id}/subpath', GET='boudin')
# routes.connect(b'/foo/{id}/bar/{sub}', something='x')
# print(routes.follow(b'/foo/id/bar/sub'))
routes.connect(path=b'/user/', GET='boudin')
routes.connect(path=b'/horse/{id}/subpath', GET='boudin')

routes.dump()
node = routes.follow(b'/user/')
print('/user/', node)
node = routes.follow(b'/horse/22/subpath')
print('/horse/22/subpath', node)
node = routes.follow(b'/plane/')
print('/plane/', node)

total = timeit("routes.follow(b'/user/')", globals=globals(), number=100000)
print(f'First flat path:\n> {total}')

total = timeit("routes.follow(b'/horse/22/subpath')", globals=globals(),
               number=100000)
print(f'Middle path with placeholder:\n> {total}')


total = timeit("routes.follow(b'/plane/')", globals=globals(), number=100000)
print(f'Not found path:\n> {total}')
