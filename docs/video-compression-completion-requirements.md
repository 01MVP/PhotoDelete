# Video Compression Completion Requirements

## Goal

The video compression completion state should clearly tell the user what happened, how much space was saved, and what they can do next. It must remain visible until the user explicitly keeps the originals or queues them for deletion.

## User Journey

1. The user selects one or more videos.
2. The user chooses a compression quality and resolution.
3. The app compresses each selected video into a new Photos library copy.
4. The completion state summarizes the whole batch:
   - how many compressed copies were created
   - how much original space was processed
   - how large the compressed copies are
   - how much space was saved
   - whether any videos failed
5. The original videos are never deleted automatically.
6. The user can compare originals and compressed copies before deciding whether to delete originals.

## UI Requirements

- Use one completion card that matches the existing advanced-page card style.
- Put the saved space in the highest-priority position.
- Support both single-video and multi-video batches without implying that all videos share the first video's resolution.
- Keep actions visually secondary to the result:
  - primary action: compare videos
  - secondary actions: delete originals, keep originals
- If savings are not meaningful, keep the delete-original action disabled and explain that keeping originals is safer.
- If some videos fail, show a concise warning with the failed count.

## Background Behavior

- During compression, keep a persistent hint that leaving the app can pause compression on iOS versions without continued background processing.
- Do not promise guaranteed background completion unless an iOS 26 continued-processing implementation is added and verified.
