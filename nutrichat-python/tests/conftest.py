import pytest


@pytest.fixture
def base_url():
    return "https://api.nutrichat.app"


@pytest.fixture
def api_key():
    return "nutrichat_live_testkey1234567890abcdef"
