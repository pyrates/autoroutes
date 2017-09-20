from timeit import timeit
from autoroutes import Routes

PATHS = ['user/', 'user/{id}', 'user/{id}/subpath', 'user/{id}/subpath2',
         'boat/', 'boat/{id}', 'boat/{id}/subpath', 'boat/{id}/subpath2',
         'horse/', 'horse/{id}', 'horse/{id}/subpath',
         'horse/{id}/subpath2', 'bicycle/', 'bicycle/{id}',
         'bicycle/{id}/subpath2', 'bicycle/{id}/subpath']

routes = Routes()
for i, path in enumerate(PATHS):
    routes.add(path, GET=i)

node = routes.match('user/')
print('user/', node)
node = routes.match('horse/22/subpath')
print('horse/22/subpath', node)
node = routes.match('plane/')
print(node)

total = timeit("routes.match('user/')", globals=globals(), number=100000)
print(f'First flat path:\n> {total}')

total = timeit("routes.match('horse/22/subpath')",
               globals=globals(), number=100000)
print(f'Middle path with placeholder:\n> {total}')

total = timeit("routes.match('plane/')",
               globals=globals(), number=100000)
print(f'Not found path:\n> {total}')
