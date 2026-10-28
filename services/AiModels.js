.pragma library

// Built-in AI models (port of pShell services/Ai.qml builtinModels).
// format: "openai" (any OpenAI-compatible endpoint) | "anthropic"; keyId =
// the entry in the AI keys file (ai.keysFile). Ollama / g4f models are
// discovered at runtime by services/Ai.qml.
var builtin = [
    // ── Gemini ────────────────────────────────────────────────────
    { id: "gemini-2.5-flash",   name: "Gemini 2.5 Flash",
      icon: "", format: "openai", keyId: "gemini", category: "api",
      endpoint: "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions",
      model: "gemini-2.5-flash" },
    { id: "gemini-2.0-flash",   name: "Gemini 2.0 Flash",
      icon: "", format: "openai", keyId: "gemini", category: "api",
      endpoint: "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions",
      model: "gemini-2.0-flash" },
    { id: "gemini-1.5-pro",     name: "Gemini 1.5 Pro",
      icon: "", format: "openai", keyId: "gemini", category: "api",
      endpoint: "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions",
      model: "gemini-1.5-pro" },

    // ── Anthropic ─────────────────────────────────────────────────
    { id: "claude-opus-5-5",    name: "Claude Opus 5.5",
      icon: "", format: "anthropic", keyId: "anthropic", category: "api",
      endpoint: "", model: "claude-opus-5-5" },
    { id: "claude-sonnet-5-5",  name: "Claude Sonnet 5.5",
      icon: "", format: "anthropic", keyId: "anthropic", category: "api",
      endpoint: "", model: "claude-sonnet-5-5" },
    { id: "claude-haiku-5-5",   name: "Claude Haiku 5.5",
      icon: "", format: "anthropic", keyId: "anthropic", category: "api",
      endpoint: "", model: "claude-haiku-5-5" },
    { id: "claude-opus-4-8",    name: "Claude Opus 4.8",
      icon: "", format: "anthropic", keyId: "anthropic", category: "api",
      endpoint: "", model: "claude-opus-4-8" },
    { id: "claude-sonnet-4-6",  name: "Claude Sonnet 4.6",
      icon: "", format: "anthropic", keyId: "anthropic", category: "api",
      endpoint: "", model: "claude-sonnet-4-6" },
    { id: "claude-haiku-4-5",   name: "Claude Haiku 4.5",
      icon: "", format: "anthropic", keyId: "anthropic", category: "api",
      endpoint: "", model: "claude-haiku-4-5-20251001" },
    { id: "claude-3-5-sonnet",  name: "Claude 3.5 Sonnet",
      icon: "", format: "anthropic", keyId: "anthropic", category: "api",
      endpoint: "", model: "claude-3-5-sonnet-20241022" },

    // ── OpenAI ────────────────────────────────────────────────────
    { id: "gpt-4o",             name: "GPT-4o",
      icon: "", format: "openai", keyId: "openai", category: "api",
      endpoint: "https://api.openai.com/v1/chat/completions",
      model: "gpt-4o" },
    { id: "gpt-4o-mini",        name: "GPT-4o mini",
      icon: "", format: "openai", keyId: "openai", category: "api",
      endpoint: "https://api.openai.com/v1/chat/completions",
      model: "gpt-4o-mini" },
    { id: "o1-mini",            name: "o1-mini",
      icon: "", format: "openai", keyId: "openai", category: "api",
      endpoint: "https://api.openai.com/v1/chat/completions",
      model: "o1-mini" },

    // ── Mistral ───────────────────────────────────────────────────
    { id: "mistral-medium-3",   name: "Mistral Medium 3",
      icon: "", format: "openai", keyId: "mistral", category: "api",
      endpoint: "https://api.mistral.ai/v1/chat/completions",
      model: "mistral-medium-2505" },
    { id: "mistral-small",      name: "Mistral Small 3.2",
      icon: "", format: "openai", keyId: "mistral", category: "api",
      endpoint: "https://api.mistral.ai/v1/chat/completions",
      model: "mistral-small-2506" },

    // ── DeepSeek ──────────────────────────────────────────────────
    { id: "deepseek-v3",        name: "DeepSeek V3",
      icon: "", format: "openai", keyId: "deepseek", category: "api",
      endpoint: "https://api.deepseek.com/v1/chat/completions",
      model: "deepseek-chat" },
    { id: "deepseek-r1",        name: "DeepSeek R1",
      icon: "", format: "openai", keyId: "deepseek", category: "api",
      endpoint: "https://api.deepseek.com/v1/chat/completions",
      model: "deepseek-reasoner" },

    // ── xAI ───────────────────────────────────────────────────────
    { id: "grok-2",             name: "Grok 2",
      icon: "", format: "openai", keyId: "xai", category: "api",
      endpoint: "https://api.x.ai/v1/chat/completions",
      model: "grok-2" },

    // ── Groq ──────────────────────────────────────────────────────
    { id: "groq-llama3-70b",    name: "Groq LLaMA 3.1 70B",
      icon: "", format: "openai", keyId: "groq", category: "api",
      endpoint: "https://api.groq.com/openai/v1/chat/completions",
      model: "llama-3.1-70b-versatile" },
    { id: "groq-llama3-8b",     name: "Groq LLaMA 3.1 8B",
      icon: "", format: "openai", keyId: "groq", category: "api",
      endpoint: "https://api.groq.com/openai/v1/chat/completions",
      model: "llama-3.1-8b-instant" },

    // ── Perplexity ────────────────────────────────────────────────
    { id: "perplexity-sonar",   name: "Perplexity Sonar",
      icon: "", format: "openai", keyId: "perplexity", category: "api",
      endpoint: "https://api.perplexity.ai/chat/completions",
      model: "llama-3.1-sonar-large-128k-online" },

    // ── OpenRouter ────────────────────────────────────────────────
    { id: "openrouter-auto",    name: "OpenRouter Auto",
      icon: "", format: "openai", keyId: "openrouter", category: "api",
      endpoint: "https://openrouter.ai/api/v1/chat/completions",
      model: "openai/auto" },
    { id: "openrouter-deepseek-r1", name: "OpenRouter DeepSeek R1",
      icon: "", format: "openai", keyId: "openrouter", category: "api",
      endpoint: "https://openrouter.ai/api/v1/chat/completions",
      model: "deepseek/deepseek-r1" },
];
