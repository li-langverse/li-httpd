#!/usr/bin/env python3
"""One-shot: port vhost fields from lic 2c448e57 onto main li_rt_net.c (run from lic repo root)."""
from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2] / "li" / "lic"
if len(sys.argv) > 1:
    ROOT = Path(sys.argv[1])
NET = ROOT / "runtime" / "li_rt_net.c"
VHOST = subprocess.check_output(["git", "show", "2c448e57:runtime/li_rt_net.c"], cwd=ROOT, text=True)


def main() -> int:
    text = NET.read_text(encoding="utf-8")
    vhost = VHOST

    text = text.replace("#define HTTPD_MAX_ROUTES 16", "#define HTTPD_MAX_ROUTES 128")
    text = text.replace("#define HTTPD_MAX_UPSTREAM_PEERS 8", "#define HTTPD_MAX_UPSTREAM_PEERS 32")

    if "char host[256]" not in text:
        text = text.replace(
            "  int content_length;\n} httpd_req_info_t;",
            "  int content_length;\n  char host[256];\n  int host_len;\n} httpd_req_info_t;",
        )

    if "char vhost[256]" not in text:
        text = text.replace(
            "  int is_proxy;\n  int rate_limit_rps;",
            "  int is_proxy;\n  char pool_id[64];\n  char vhost[256];\n  int rate_limit_rps;",
        )

  # inject helpers from vhost tree
    m = re.search(
        r"static void parse_request_host_c\([\s\S]*?^static int route_vhost_match",
        vhost,
        re.MULTILINE,
    )
    if m and "parse_request_host_c" not in text:
        block = m.group(0)
        anchor = "static void parse_request_body_meta_c"
        text = text.replace(anchor, block + "\n\n" + anchor, 1)

    if "route_vhost_match" in text and "if (!route_vhost_match(r, req))" not in text:
        for fn in (
            "path_proxy_match_route",
            "httpd_route_requires_traceparent_for",
            "httpd_route_requires_websocket_for",
            "httpd_match_route_index",
        ):
            text = re.sub(
                rf"(static int {fn}\([^\{{]+\{{[\s\S]*?if \(!route_method_match\(r, req\)\) \{{\s*continue;\s*\}})",
                r"\1\n    if (!route_vhost_match(r, req)) {\n      continue;\n    }",
                text,
                count=1,
            )

    # route parser: extend to pool/vhost (copy from vhost file section)
    if "fields_are_rate_limits" not in text:
        rp = re.search(
            r"static int fields_are_rate_limits[\s\S]*?if \(part_n >= 4\) \{[\s\S]*?g_route_count\+\+;\s*\}",
            vhost,
        )
        if rp:
            text = re.sub(
                r"\} else if \(strcmp\(key, \"route\"\) == 0[\s\S]*?g_route_count\+\+;\s*\}\s*\}",
                rp.group(0).replace("} else if (strcmp(key, \"route\")", "} else if (strcmp(key, \"route\")", 1),
                text,
                count=1,
            )

    # upstream_peer pool|host|port
    if 'strcmp(key, "upstream_pool")' not in text:
        text = text.replace(
            '} else if (strcmp(key, "upstream_peer") == 0) {\n'
            "      int port = atoi(val);\n"
            "      if (port > 0) {\n"
            "        httpd_add_upstream_peer_i(port);\n"
            "        g_proxy_port = port;\n"
            "      }",
            '} else if (strcmp(key, "upstream_pool") == 0) {\n'
            "      (void)val;\n"
            '    } else if (strcmp(key, "upstream_peer") == 0) {\n'
            '      char pool[64] = "";\n'
            '      char host[64] = "127.0.0.1";\n'
            '      char* p1 = strchr(val, \'|\');\n'
            "      if (p1) {\n"
            "        *p1 = '\\0';\n"
            "        snprintf(pool, sizeof(pool), \"%s\", val);\n"
            "        char* p2 = strchr(p1 + 1, '|');\n"
            "        if (p2) {\n"
            "          *p2 = '\\0';\n"
            "          snprintf(host, sizeof(host), \"%s\", p1 + 1);\n"
            "          int port = atoi(p2 + 1);\n"
            "          if (port > 0) {\n"
            "            httpd_add_upstream_peer_pool_i((intptr_t)pool, (intptr_t)host, port);\n"
            "            g_proxy_port = port;\n"
            "          }\n"
            "        }\n"
            "      } else {\n"
            "        int port = atoi(val);\n"
            "        if (port > 0) {\n"
            "          httpd_add_upstream_peer_i(port);\n"
            "          g_proxy_port = port;\n"
            "        }\n"
            "      }",
        )

    if "parse_request_host_c" in text:
        text = text.replace(
            "  parse_request_body_meta_c(g_slots[slot].buf, hdr_end, &req);\n",
            "  parse_request_body_meta_c(g_slots[slot].buf, hdr_end, &req);\n"
            "  parse_request_host_c(g_slots[slot].buf, hdr_end, &req);\n",
            1,
        )

    text = text.replace(
        "  if (g_up_peer_count > 0) {\n    upstream_pool_prewarm_all();\n  }",
        "  /* Defer blocking prewarm: dead NodePorts stall startup before listen bind. */\n"
        "  if (0 && g_up_peer_count > 0) {\n    upstream_pool_prewarm_all();\n  }",
    )

    NET.write_text(text, encoding="utf-8")
    print(f"patched {NET}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
