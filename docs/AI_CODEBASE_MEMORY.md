# AI Agent Guide: Codebase Memory

## Overview
This repository contains a pre-built knowledge graph database located at `.codebase-memory/graph.db`. This file was generated using the `codebase-memory-mcp` and is committed to the repository to speed up AI context gathering for all team members.

## Instructions for AI Agents
If you (the AI Assistant) are reading this and you have access to `codebase-memory-mcp` tools, please adhere to the following rules:

1. **Do Not Re-index Automatically:** The `.codebase-memory/graph.db` file already contains the parsed architecture, node references, and relationships. You do not need to run a full `index_repository` from scratch unless the human explicitly asks you to update the index.
2. **Leverage the Memory Graph:** Prioritize using MCP tools over standard `grep` or file searches when trying to understand code relationships.
   - Use `search_graph` to find references to classes, functions, or specific logic.
   - Use `trace_path` to understand how components interact with each other.
   - Use `get_architecture` to quickly grab the high-level summary.
3. **Local Cache Fallback:** If the `graph.db` is available here, it acts as a persistent memory. If you update the index during your session, remind the user to commit the updated `graph.db` so the rest of the team gets the latest structural knowledge.

## For Human Developers
- **What is this?** This `.codebase-memory/graph.db` file helps your AI coding assistants instantly understand how all the scripts, configuration files, and apps in this project relate to one another without having to read thousands of lines of code manually.
- **Maintenance:** If you add new apps, rename core scripts, or significantly change the architecture, ask your AI to "update the codebase memory index and overwrite the graph.db". Then commit the changes.
