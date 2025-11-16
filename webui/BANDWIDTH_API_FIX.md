# Bandwidth API Bug Fix

## Problem

The bandwidth history API endpoint was failing with:

```
TypeError: 'str' object is not callable
File "/nix/store/.../backend/api/bandwidth.py", line 136, in get_bandwidth_history
    for i in range(len(data_points)):
             ^^^^^^^^^^^^^^^^^^^^^^^
```

## Root Cause

**Variable Shadowing**: The function parameter was named `range`, which shadows Python's built-in `range()` function.

```python
# Before (broken)
async def get_bandwidth_history(
    range: str = Query("1h", ...),  # ❌ Shadows built-in range()
    ...
):
    for i in range(len(data_points)):  # ❌ Tries to call the string parameter
```

When the code tried to use `range()` for iteration, Python attempted to call the string parameter `"1h"` as a function, causing the TypeError.

## Solution

Renamed the parameter to `time_range` and used `alias="range"` to maintain API compatibility:

```python
# After (fixed)
async def get_bandwidth_history(
    time_range: str = Query("1h", ..., alias="range"),  # ✅ No shadowing
    ...
):
    for i in range(len(data_points)):  # ✅ Uses built-in range()
```

The `alias="range"` ensures the frontend can still use `?range=1h` in the URL.

## Impact

- ✅ Bandwidth history API now works correctly
- ✅ Network bandwidth charts display data
- ✅ API compatibility maintained (still accepts `?range=` parameter)
- ✅ No frontend changes needed

## Files Changed

- `webui/backend/api/bandwidth.py` - Fixed parameter name shadowing

## Verification

```bash
# On your router, after rebuild:
sudo journalctl -u router-webui-backend -f

# Should see successful requests:
INFO: 192.168.2.11:43192 - "GET /api/bandwidth/history?interface=ppp0&range=1h HTTP/1.1" 200 OK
```

## Lesson

**Never shadow Python built-ins!** Common ones to avoid as variable names:
- `range`, `len`, `list`, `dict`, `str`, `int`, `float`, `type`
- `id`, `input`, `open`, `file`, `dir`, `sum`, `max`, `min`
- `filter`, `map`, `zip`, `sorted`, `reversed`

Always use descriptive names like `time_range`, `data_len`, `items_list`, etc.

