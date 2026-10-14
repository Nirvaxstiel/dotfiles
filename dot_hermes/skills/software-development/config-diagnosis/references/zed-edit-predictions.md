# Zed edit predictions over an OpenAI-compatible endpoint

Concrete instance of the config-diagnosis procedure: the Zed editor's
`edit_predictions.open_ai_compatible_api` provider, and the gateway-side facts
that make it fail. Load this when a Zed autocomplete/edit-prediction config
produces no suggestions, or logs `custom server error`.

## Settings schema

`crates/settings_content/src/language.rs` — `EditPredictionSettingsContent` and
`CustomEditPredictionProviderSettingsContent`.

| Key | Values | Default |
|-----|--------|---------|
| `provider` | `none`, `copilot`, `codestral`, `ollama`, `open_ai_compatible_api`, `zed`, `mercury` | `zed` |
| `allow_data_collection` | `default`, `yes`, `no` | `default` |
| `open_ai_compatible_api.api_url` | full request URI, used **verbatim** (no path appended) | `""` |
| `open_ai_compatible_api.model` | model ID sent in the request body | `""` |
| `open_ai_compatible_api.prompt_format` | `infer`, `zeta`, `zeta2`, `zeta2_1`, `code_llama`, `star_coder`, `deepseek_coder`, `qwen`, `code_gemma`, `codestral`, `glm`, `sweep` | `infer` |
| `open_ai_compatible_api.max_output_tokens` | u32 | 256 |
| `open_ai_compatible_api.prediction_debounce` | ms; `0` disables the extra delay | 0 |

There is **no `api_key` setting**. The token comes from the
`ZED_OPEN_AI_COMPATIBLE_EDIT_PREDICTION_API_KEY` environment variable or the
system keychain, and is sent as `Authorization: Bearer <token>`.

## Wire contract — legacy completions, not chat

`crates/edit_prediction/src/open_ai_compatible.rs` posts to `api_url` verbatim:

```json
{"model": "...", "prompt": "...", "max_tokens": 512, "stop": ["..."]}
```

and parses `choices[].text`. That is the **legacy OpenAI `/v1/completions`**
shape. `/chat/completions` takes `messages` and returns `choices[].message`, so it
fails both at request validation and at response parsing. `api_url` must be the
full `.../v1/completions` endpoint of whatever gateway fronts the model.

Failures surface in the log as `custom server error: <status> - <body>` or
`Failed to parse completion response`. Read them with `zed: open log`.

## Why it silently does nothing: `prompt_format: "infer"`

`crates/zed/src/zed/edit_prediction_registry.rs` resolves the format, and on a
failed inference it drops the provider config outright:

```rust
let mut format = custom_settings.prompt_format;
if format == EditPredictionPromptFormat::Infer {
    if let Some(inferred_format) = fim::infer_prompt_format(&custom_settings.model) {
        format = inferred_format;
    } else {
        return None;   // no request is ever sent, no error is shown
    }
}
```

`infer_prompt_format` (`crates/edit_prediction/src/fim.rs`) strips the `:tag`
suffix, then requires an **exact** match against a fixed list:

`zeta2`, `zeta2.1`, `*sweep-next-edit*`, `codellama`, `code-llama`,
`starcoder`, `starcoder2`, `starcoderbase`, `deepseek-coder`,
`deepseek-coder-v2`, `qwen2.5-coder`, `qwen-coder`, `qwen`, `codegemma`,
`codestral`, `mistral`, `glm`, `glm-4`, `glm-4.5`.

A gateway-namespaced model ID such as `vendor/model-name:free` reduces to
`vendor/model-name`, matches no arm, and disables edit predictions entirely.
**Set `prompt_format` explicitly whenever the model ID is namespaced.**

## OpenRouter

- Route: `https://openrouter.ai/api/v1/completions` — legacy text completions,
  `object: "text_completion"`, `choices[].text`. This is the route Zed needs.
  `/api/v1/chat/completions` is the wrong one.
- Route-existence probe, no credentials needed: `POST` the real path → 401
  (auth-gated, exists); `POST` a bogus path → 404.
- OpenRouter's published spec at `https://openrouter.ai/openapi.json` lists no
  `/completions` path even though the route is live. Do not treat a spec's path
  list as authoritative — probe it.
- Legacy-route support is per model and per upstream provider. A 4xx means the
  model is not served over that route: pick a FIM/coder model and set
  `prompt_format` to a name the inference list above recognises.

## Known-good shape

```json
"edit_predictions": {
  "provider": "open_ai_compatible_api",
  "allow_data_collection": "no",
  "open_ai_compatible_api": {
    "max_output_tokens": 512,
    "model": "<gateway>/<model>",
    "api_url": "https://openrouter.ai/api/v1/completions",
    "prompt_format": "qwen"
  }
}
```

`settings.json` is JSON5 — comments and trailing commas are valid, which is why
JSON-validating write tools refuse to edit it. Restart Zed after the change;
reloading the window does not re-read the provider config.
