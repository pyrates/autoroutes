# Autoroutes

Routes for speed.


## Install

    pip install autoroutes


## API

```python
# Create a Routes instance
from autoroutes import Routes
routes = Routes()

# Register a new path
routes.connect('path/to/resource/{id}', something='value', anything='else')

# Try to match a path
routes.follow('path/to/resource/1234')
> ({'something': 'value', 'anything': 'else'}, {'id': '1234'})
```

### Placeholders

Placeholders are defined by a curly brace pair: `path/{var}`. By default, this
will match any character but the slash ('/') (`[^/]+`).

It's possible to control the placeholder type, either by:
- using a named type: `w`/`word`, `i`/`int`, `*`/`path`, `s`/`string`:

        path/to/{var:int}

- using a simple (optimizable) pattern: `\w+`, `[0-9a-z]+`, `[a-z0-9]+`,
  `[a-z]+`, `\d+`, `[0-9]+`, `[^-]+`, `.+`

        path/to/{var:\d+}

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

## Acknowledgements

This package has been first made as a Cython port of the [R3](https://github.com/c9s/r3/)
C router.
See also [python-r3](https://framagit.org/ybon/python-r3), which was a first
attempt to wrap R3. I was unhappy with the stability, and more curious about
Cython, so I tried to make a first POC port, and was happy with it.
