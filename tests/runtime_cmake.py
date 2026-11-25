"""runtime/CMakeLists.txt as one text, for the tests that check the build by reading it.

The build file keeps its large blocks in runtime/cmake/*.cmake and includes them. ``read()`` puts the text of each
included file after its include() line, indented like that line, so a test sees every target and every add_test() of
the build in the order CMake reads them.
"""
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CMAKE_LISTS = ROOT / "runtime" / "CMakeLists.txt"

_INCLUDE = re.compile(r'^([ \t]*)include\("\$\{CMAKE_CURRENT_SOURCE_DIR\}/(cmake/[A-Za-z0-9_.-]+\.cmake)"\)[ \t]*$')


def read(path=CMAKE_LISTS):
    """The text of ``path`` with the file of every ``include("${CMAKE_CURRENT_SOURCE_DIR}/cmake/<name>.cmake")`` line
    inserted after that line. Included files are looked up next to ``path`` and are not expanded themselves; one that
    does not exist is an error."""
    path = Path(path)
    out = []
    for line in path.read_text(encoding="utf-8").splitlines():
        out.append(line)
        include = _INCLUDE.match(line)
        if include:
            indent, part = include.group(1), path.parent / include.group(2)
            out.extend(indent + inner if inner else "" for inner in part.read_text(encoding="utf-8").splitlines())
    return "\n".join(out) + "\n"
