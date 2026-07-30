#!/usr/bin/env python3
"""Delete specific payload paths from the shipped HF dataset.

Used when a row leaves the catalog for a reason that also means its payload
should stop being served — a content hold, not a re-tiering. Re-emitting the
catalog alone is not enough: the catalog stops advertising the file, but the
bytes remain fetchable at their old path.

⚠️ THIS REMOVES THE FILE FROM `main` ONLY. HuggingFace keeps detached commits
reachable by SHA, so `resolve/<old-sha>/<path>` can still serve it. A real purge
is delete_repo + create_repo + re-upload of the clean dirs (see ../hf_ops.md §7,
where squashing was found insufficient). That is proportionate for a licence
violation; for a content hold, ask the maintainer whether it is worth the
~7 GB re-upload before doing it.
"""
import sys

from huggingface_hub import HfApi

REPO = "cstr/cometbeat-assets"


def main():
    paths = [ln.strip() for ln in open(sys.argv[1]) if ln.strip()]
    api = HfApi()
    existing = set(api.list_repo_files(REPO, repo_type="dataset"))
    todo = [p for p in paths if p in existing]
    print(f"{len(paths)} requested · {len(todo)} present in the repo")
    if not todo:
        return
    api.delete_files(repo_id=REPO, repo_type="dataset", delete_patterns=todo,
                     commit_message=f"content hold: remove {len(todo)} payloads")
    still = set(api.list_repo_files(REPO, repo_type="dataset"))
    left = [p for p in todo if p in still]
    print(f"deleted {len(todo) - len(left)} · still present {len(left)}")
    for p in left[:10]:
        print("   !!", p)


if __name__ == "__main__":
    main()
