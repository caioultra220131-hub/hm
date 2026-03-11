## [ERR-20260311-001] hvigor-cache-workspace-missing

**Logged**: 2026-03-11T00:00:00+08:00
**Priority**: high
**Status**: pending
**Area**: config

### Summary
Hvigor failed because the cached workspace under the user profile was partially broken.

### Error
```text
ENOENT: no such file C:\Users\lasrorder\.hvigor\project_caches\bf05a3c616a7644b20dd9de65613704b32b314679bec6d21d32d4e47b72a95ea\workspace\node_modules\@ohos\hvigor\bin\hvigor.js
```

### Context
- Command attempted: `hvigorw.bat tasks --mode project -p product=simulator`
- Environment: DevEco Studio Hvigor on Windows
- Follow-up sandbox retry hit `EPERM` when Hvigor tried to recreate the same cache under `C:\Users\lasrorder\.hvigor`

### Suggested Fix
Delete the specific broken cache workspace under `.hvigor/project_caches/.../workspace` and rerun the build outside the sandbox so Hvigor can recreate its cache.

### Metadata
- Reproducible: unknown
- Related Files: .hvigor/outputs/build-logs/build.log

---
