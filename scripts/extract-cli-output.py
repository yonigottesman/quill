#!/usr/bin/env python3
# Extracts the model generation from `llama cli` stdout. stdout contains a banner,
# the echoed prompt (`> <user text>`), the generation, then a `[ Prompt: ... ]`
# stats line. We anchor on the echoed user text (passed as a file path in argv[1])
# and return everything after its last line, up to the stats line, trimmed.
import sys, re

user_path = sys.argv[1]
with open(user_path) as f:
    user = f.read().strip()

data = sys.stdin.read()
data = re.sub(r"\x1b\[[0-9;]*[A-Za-z]", "", data)        # strip ANSI
data = data.replace("\r", "")
data = re.sub(r"[\x00-\x08\x0b\x0c\x0e-\x1f]", "", data)  # strip control chars (\b spinner etc.), keep \n\t
lines = data.split("\n")

# End boundary: the stats line.
end = len(lines)
for i, ln in enumerate(lines):
    if ln.lstrip().startswith("[ Prompt:"):
        end = i
        break

# Start boundary: the last line of the echoed user prompt. The echo begins with
# "> " + first user line; its final line equals the user's last line.
user_last = user.split("\n")[-1].strip()
start = 0
for i in range(end - 1, -1, -1):
    s = lines[i].strip()
    if s == user_last or s == "> " + user_last or s.lstrip("> ").strip() == user_last:
        start = i + 1
        break

out = "\n".join(lines[start:end]).strip()
# llama cli prefixes the response with a "|" spinner/marker decoration.
if out.startswith("|"):
    out = out[1:]
sys.stdout.write(out.strip())
