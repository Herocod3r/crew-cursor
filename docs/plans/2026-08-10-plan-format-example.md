---
slug: rate-limit-auth
phase: gate1
size: full
gates: { g1: false, g2: false }
critique: { verdict: PROCEED, blocker: 0, major: 0, minor: 2, round: 1 }
pr: null
updated: 2026-08-10
---

<!-- SPECIMEN. Not a real run. The repository, paths and line numbers below are invented,
     and exist to show what a crew plan.md looks like after the format change in
     docs/plans/2026-08-10-plan-format-design.md. -->

# Rate limit the auth endpoints

## Goal

A request to reset a password or to log in is refused after five attempts for the same email
address within fifteen minutes. Done means a sixth attempt returns 429 with the service's normal
error shape, the refusal is identical whether or not the address exists, and both limits survive
a process restart.

## Why

`api/routes/auth.py:88` calls `send_reset_email` with nothing between the request and the send,
so one address can be mailed as fast as the client can loop. `api/routes/auth.py:41` has the
same shape for login, which turns the endpoint into a password oracle at whatever rate the
attacker can drive it. Both were reported in `SEC-2291`.

There is no limiter to reuse. `api/middleware.py` has a global per-IP cap (`:34`), which does
not help here: the attacks that matter come from many addresses at one account, not many
requests from one address.

## Architecture

A `RateLimiter` over the Redis instance the session store already uses, keyed by purpose and
email, counting into a fixed window. The two routes call it before doing any work, so a refused
request costs one Redis round trip and never touches the database.

## Tech Stack

Python 3.12, FastAPI, Redis 7, pytest with `fakeredis` for the unit tests.

## Decisions

| Decision | Rationale | Rejected |
|---|---|---|
| Fixed window, not a token bucket | Five in fifteen minutes has no burst requirement, and a fixed window is one `INCR` and one `EXPIRE`. A bucket needs a stored timestamp and a refill calculation | Token bucket; a sliding log |
| Reuse the session Redis, do not add one | It is already a hard dependency of every authenticated request, so it adds no new failure mode. A second store would | A dedicated Redis; an in-process counter |
| Extend the per-IP middleware? No | It keys on IP (`api/middleware.py:34`) and both attacks come from one address across many IPs. Rekeying it would change behaviour for every route that relies on it | Adding an email key to the existing middleware |
| Fail open when Redis is down | Locking every user out of login because a cache is unavailable trades a rate-limit bypass for an outage. The bypass is logged and alerts | Fail closed |

## Assumptions

| Assumption | Basis |
|---|---|
| The session Redis has spare capacity for two keys per auth attempt | Approved by the human. Current peak is 40 auth requests per second, so about 80 keys per second against an instance sized for 12,000 operations per second |

## Global Constraints

- Every 429 response uses the existing problem+json body from `api/errors.py:20`. No new shape.
- No auth response may differ by whether the email exists. Same status, same body, same timing
  class, whether limited or not.
- `redis>=5.0` is already in `pyproject.toml`. Do not add a dependency for this work.
- Limits are `5` attempts per `900` seconds. Both values are configuration, not literals in a
  route.

## Approach

```
 POST /auth/login ─────┐
                       ├──> RateLimiter.check(key) ──false──> 429 problem+json
 POST /auth/reset ─────┘             │
                                    true
                                     ↓
                              existing handler
```

| File | Responsibility |
|---|---|
| `api/ratelimit.py` | New. The counter and its Redis keys. Knows nothing about auth |
| `api/routes/auth.py` | Calls the limiter before the login and reset handlers do any work |
| `api/config.py` | Holds the two limit values |
| `tests/test_ratelimit.py` | The limiter against `fakeredis`, including the fail-open path |
| `tests/routes/test_auth.py` | Both endpoints refuse the sixth attempt and reveal nothing |

Both endpoints are one task because they are one file. Ownership is per path across the whole
plan, not per wave, so two tasks cannot both name `api/routes/auth.py`.

## Tasks

### t1: the rate limiter

```yaml
id: t1
needs: []
files:
  - api/ratelimit.py
  - api/config.py                  # add the two settings beside SESSION_TTL, line 30
  - tests/test_ratelimit.py
generates: []
verify: "pytest tests/test_ratelimit.py -q"
```

**Interfaces**

- Consumes: nothing.
- Produces:
  - `RateLimiter(redis: Redis)`
  - `RateLimiter.check(self, key: str) -> bool`
  - `settings.AUTH_ATTEMPT_LIMIT: int`
  - `settings.AUTH_ATTEMPT_WINDOW_S: int`

- [ ] **Write the failing test**

```python
def test_sixth_attempt_in_window_is_refused(fake_redis):
    limiter = RateLimiter(fake_redis)
    assert all(limiter.check("login:a@b.com") for _ in range(5))
    assert limiter.check("login:a@b.com") is False

def test_check_returns_true_when_redis_is_down(broken_redis):
    assert RateLimiter(broken_redis).check("login:a@b.com") is True
```

- [ ] **Run it.** `pytest tests/test_ratelimit.py -q`
      Expect FAIL with `ImportError: cannot import name 'RateLimiter'`.

- [ ] **Write `api/ratelimit.py`**

```python
import logging

from redis import Redis
from redis.exceptions import RedisError

from api.config import settings

log = logging.getLogger(__name__)


class RateLimiter:
    def __init__(self, redis: Redis) -> None:
        self._redis = redis

    def check(self, key: str) -> bool:
        """False when the caller has used its allowance. True when Redis is unreachable."""
        try:
            with self._redis.pipeline() as pipe:
                count, _ = pipe.incr(key).expire(
                    key, settings.AUTH_ATTEMPT_WINDOW_S, nx=True
                ).execute()
        except RedisError:
            log.warning("rate limit bypassed, redis unavailable", extra={"key": key})
            return True
        return count <= settings.AUTH_ATTEMPT_LIMIT
```

`expire` takes `nx=True` so the window starts at the first attempt and is not pushed forward by
each later one. Without it the window never closes while attempts keep arriving.

- [ ] **Add the two settings to `api/config.py`,** beside `SESSION_TTL` at line 30

```python
AUTH_ATTEMPT_LIMIT: int = 5
AUTH_ATTEMPT_WINDOW_S: int = 900
```

- [ ] **Run it.** Expect PASS, 2 passed.

---

### t2: refuse repeated resets and logins

Both endpoints live in `api/routes/auth.py`, and one path cannot have two owners, so they are
one task. Splitting them would mean splitting the file first, and nothing here justifies that.

```yaml
id: t2
needs: [t1]
files:
  - api/routes/auth.py             # reset handler line 88, login handler line 41
  - tests/routes/test_auth.py
generates: []
verify: "pytest tests/routes/test_auth.py -q"
```

**Interfaces**

- Consumes, verbatim from t1: `RateLimiter(redis: Redis)` and
  `RateLimiter.check(self, key: str) -> bool`.
- Produces: nothing. Leaf.

- [ ] **Write the failing test.** Both halves matter: the limit, and that it says nothing about
      whether the address is real.

```python
def test_sixth_reset_is_refused(client, known_email):
    for _ in range(5):
        client.post("/auth/reset", json={"email": known_email})
    r = client.post("/auth/reset", json={"email": known_email})
    assert r.status_code == 429
    assert r.json()["type"] == "https://errors.example.com/too-many-requests"

def test_refusal_is_identical_for_unknown_email(client, known_email, unknown_email):
    def sixth(email):
        for _ in range(6):
            r = client.post("/auth/reset", json={"email": email})
        return r
    assert sixth(known_email).json() == sixth(unknown_email).json()
```

```python
def test_sixth_login_is_refused(client, known_email):
    for _ in range(5):
        client.post("/auth/login", json={"email": known_email, "password": "wrong"})
    r = client.post("/auth/login", json={"email": known_email, "password": "wrong"})
    assert r.status_code == 429
```

- [ ] **Run it.** `pytest tests/routes/test_auth.py -q`
      Expect FAIL: the sixth reset returns 202 and the sixth login returns 401.

- [ ] **Build the limiter once, at module scope,** beside the existing `session_redis` import
      at the top of `api/routes/auth.py`

```python
from api.ratelimit import RateLimiter
from api.session import session_redis

limiter = RateLimiter(session_redis)
```

- [ ] **Add the check at the top of the reset handler,** at line 88, before it looks the user up

```python
if not limiter.check(f"reset:{body.email.lower()}"):
    raise TooManyRequests()
```

- [ ] **Add the same check at the top of the login handler,** at line 41, before the password is
      verified

```python
if not limiter.check(f"login:{body.email.lower()}"):
    raise TooManyRequests()
```

Lowercase the address before keying, in both. `A@b.com` and `a@b.com` are one account and must
share one counter, or the limit is bypassed by changing case. The two prefixes keep the reset
allowance and the login allowance separate, so exhausting one does not lock the other.

- [ ] **Run it.** Expect PASS, 3 passed.

## Wave list

```
wave 0   t1
wave 1   t2
```

Two waves and no parallelism, because there are only two tasks and the second needs the first.
Both auth endpoints are one task rather than two: they live in one file, one path can have only
one owner, and a reviewer who wanted to accept the reset limit and reject the login limit would
have to say so in review rather than by rejecting a task.

## Verify

```bash
pytest -q                                   # the whole suite, once
rg -n 'AUTH_ATTEMPT' api/ | rg -v config.py # no literal limits outside config
```

Then, against a running instance: six resets for one address returns 429 on the sixth, six for
an address that does not exist returns the same body, and `redis-cli --scan --pattern 'reset:*'`
shows the keys expiring within fifteen minutes.

## Non-goals

Per-IP limits, which `api/middleware.py` already does. Account lockout. CAPTCHA. Limiting any
endpoint other than login and password reset. Making the limits per-tenant.
