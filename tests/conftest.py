import pytest

from autoroutes import Routes


@pytest.fixture
def routes():
    routes_ = Routes()
    yield routes_
    routes_.dump()  # Will display only in case of failure.
    del routes_
