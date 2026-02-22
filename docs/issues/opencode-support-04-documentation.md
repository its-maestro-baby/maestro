# Story: OpenCode Documentation
**ID:** opencode-support-04  
**Status:** Ready for Development  
**Priority:** P1  
**Estimate:** 1 day

## User Story
As a Maestro user, I want documentation on how to install and use OpenCode with Maestro, so that I can get started quickly without guessing.

## Acceptance Criteria
- [ ] README.md updated with OpenCode in AI mode list
- [ ] README.md includes OpenCode installation instructions
- [ ] README.md shows OpenCode as a supported AI assistant
- [ ] AGENTS.md updated if needed (code examples, patterns)
- [ ] Troubleshooting guide includes OpenCode-specific issues
- [ ] All documentation links to https://opencode.ai
- [ ] npm package name correctly listed as `opencode-ai`

## Documentation Updates

### README.md Changes
**Section: Multi-AI Support (or similar)**
Add OpenCode to the list:
```markdown
### Multi-AI Support
- **Claude Code** - Anthropic's Claude in the terminal
- **Gemini CLI** - Google's Gemini AI
- **OpenAI Codex** - OpenAI's coding assistant
- **OpenCode** - AI coding assistant (https://opencode.ai)
- **Plain Terminal** - Standard shell without AI
```

**Section: Optional: Install AI CLIs**
```markdown
### Optional: Install AI CLIs

```bash
# Claude Code (recommended)
npm install -g @anthropic-ai/claude-code

# Gemini CLI
npm install -g @google/gemini-cli

# OpenAI Codex
npm install -g codex

# OpenCode
npm install -g opencode-ai
```
```

**Section: Troubleshooting**
Add:
```markdown
### OpenCode Not Found

The OpenCode CLI must be installed globally and in your PATH:
```bash
npm install -g opencode-ai
which opencode  # Should show the path
```

For more help, visit https://opencode.ai/docs/
```

### BRD Updates
**File:** `docs/specs/opencode-support-brd.md`
- Update Appendix B with correct resources
- Update all references to use `opencode-ai` package name
- Update flag references to use `--dangerously-skip-permissions`

### Code Comments
Add OpenCode references in:
- `src/lib/terminal.ts` - AI_CLI_CONFIG comment
- `src/components/terminal/CliSettingsModal.tsx` - Mode configuration

## Definition of Done
- [ ] README.md lists OpenCode as supported AI
- [ ] Installation instructions include `npm install -g opencode-ai`
- [ ] Troubleshooting section covers OpenCode
- [ ] All links to https://opencode.ai are working
- [ ] AGENTS.md updated if code patterns changed
- [ ] BRD updated with final implementation details
- [ ] Documentation reviewed for accuracy

## Checklist
- [ ] Verify npm package name: `opencode-ai`
- [ ] Verify command name: `opencode`
- [ ] Verify website: https://opencode.ai
- [ ] Verify docs: https://opencode.ai/docs/
- [ ] Verify flag: `--dangerously-skip-permissions`
- [ ] Verify GitHub: https://github.com/anomalyco/opencode

## Dependencies
- Story 01: OpenCode Mode Selection
- Story 02: OpenCode Session Launch
- Story 03: OpenCode CLI Settings

## Notes
This should be the final story - documentation is written after implementation is complete so it's accurate.

## Resources
- **Website:** https://opencode.ai
- **Docs:** https://opencode.ai/docs/
- **Config:** https://opencode.ai/docs/config/
- **GitHub:** https://github.com/anomalyco/opencode
