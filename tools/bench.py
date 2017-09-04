from timeit import timeit
from autoroutes import Routes, NoRoute

PATHS = ['user/', 'user/{id}', 'user/{id}/subpath', 'user/{id}/subpath2',
         'boat/', 'boat/{id}', 'boat/{id}/subpath', 'boat/{id}/subpath2',
         'horse/', 'horse/{id}', 'horse/{id}/subpath',
         'horse/{id}/subpath2', 'bicycle/', 'bicycle/{id}',
         'bicycle/{id}/subpath2', 'bicycle/{id}/subpath',
         '{foo}/{bar}/{baz}/{last}', 'api/{bar}/{baz}/{last}', 'api/id']

routes = Routes()
for i, path in enumerate(PATHS):
    routes.connect(path.encode(), GET=i)

node = routes.follow(b'user/')
print('user/', node)
node = routes.follow(b'horse/22/subpath')
print('horse/22/subpath', node)
node = routes.follow(b'api/id/baz/last')
print('api/id/baz/last', node)
try:
    routes.follow(b'plane/')
except NoRoute:
    print('plane/ not found')
else:
    print('Oops, not raised')

total = timeit("routes.follow(b'user/')", globals=globals(), number=100000)
print(f'First flat path:\n> {total}')

total = timeit("routes.follow(b'horse/22/subpath')", globals=globals(),
               number=100000)
print(f'Middle path with placeholder:\n> {total}')

total = timeit("try:\n routes.follow(b'plane/')\nexcept NoRoute:\n pass",
               globals=globals(), number=100000)
print(f'Not found path:\n> {total}')
