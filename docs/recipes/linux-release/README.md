# Linux consumer release recipe

These files build a consumer application for Oracle Linux 8.5, x86_64, and
glibc 2.28. They are build inputs, not a runnable TermUI example. The recipe
addresses the native-library compatibility failure reported in issue #10.

Read [the Linux release guide](../../../guides/linux-releases.md) before use.
Copy `Dockerfile` and `dockerignore` into the consumer as `Dockerfile` and
`.dockerignore`. Set its release name and commit its dependency lockfile.

The recipe builds ERTS and native dependencies for that target. It is not a
general container image for every Linux system. Keep it outside the Hex package.
