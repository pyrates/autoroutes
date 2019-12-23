# Autoroutes

Routes for speed.


## Install

    pip install autoroutes


## API

```python
# Create a Routes instance
from autoroutes import Routes
routes = Routes()

# Register a new route
routes.add('path/to/resource/{id}', something='value', anything='else')

# Try to match a route
routes.match('path/to/resource/1234')
> ({'something': 'value', 'anything': 'else'}, {'id': '1234'})
```

### Placeholders

Placeholders are defined by a curly brace pair: `path/{var}`. By default, this
will match any character but the slash ('/').

It's possible to control the placeholder type, either by:
- using a named type: `alnum`, `digit`, `alpha`, `path` (matches everything),
  `string` (default):

        path/to/{var:digit}
        path/to/{var:string}  # Same as path/to/{var}

- using a normal regex (slower; also note that regex containing curly braces is
  not yet supported)

        path/to/{var:\d\d\d}

Placeholders can appear anywhere in the path

    path/to/file.{ext}
    path/to/{name}.{ext}


## Building from source

    pip install cython
    make compile
    python setup.py develop


## Tests

    make test

## Benchmark

![](https://raw.githubusercontent.com/pyrates/autoroutes/master/benchmark.png)

See [Benchmark](https://github.com/pyrates/autoroutes/wiki/Benchmark) for more
details.

## Acknowledgements

This package has been first made as a Cython port of the [R3](https://github.com/c9s/r3/)
C router.
See also [python-r3](https://framagit.org/ybon/python-r3), which was a first
attempt to wrap R3. I was unhappy with the stability, and more curious about
Cython, so I tried to make a first POC port, and was happy with it.
