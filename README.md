# KOReader GPT Plugin

A plugin for KOReader that adds GPT capabilities through OpenRouter API integration. Select text in your books and quickly get explanations, translations, summaries, and more using various AI models.

## Features

- Integrates with KOReader's text selection menu
- Dynamic model selection from OpenRouter's available models
- Custom task creation and management
- Response caching
- Settings persistence
- Configurable system prompts

## Installation

1. Copy the `koreader-gpt` folder to your KOReader plugins directory:
   ```
   /path/to/koreader/plugins/
   ```

2. Restart KOReader

3. Configure the plugin:
   - Go to Settings
   - Enter your OpenRouter API key
   - Select your preferred model from the available models list
   - Customize the system prompt if desired

## Usage

1. Select text in any book
2. Tap "Ask GPT" in the selection menu
3. Choose a task or enter a custom prompt
4. View the AI response in a movable window

## Creating Custom Tasks

1. Go to the plugin settings
2. Select "Manage Tasks"
3. Tap "Add New Task"
4. Enter:
   - Task Name (e.g., "Thai Translation")
   - Prompt (e.g., "Translate this text to modern Thai")
5. Save the task

Your custom task will now appear in the task list when using the plugin.

## Default Tasks

- Explain - Get a simple explanation of the selected text
- Summarize - Get a concise summary
- Translate to English - Translate the selected text to English

## Model Selection

The plugin dynamically fetches available models from OpenRouter's API. For each model, you can view:
- Model name and description
- Context length (maximum tokens)
- Pricing information (per million tokens)
  - Prompt cost
  - Completion cost

To select a model:
1. Go to Settings
2. Tap "Select Model"
3. Choose from the list of available models
4. Hold on any model to view detailed information

Models are automatically updated when you open the model selector.

## Error Handling

The plugin includes robust error handling for:
- Network issues
- Invalid API keys
- Rate limiting
- API errors
- Model fetching failures

## Caching

Responses are cached locally to:
- Reduce API calls
- Provide faster responses for repeated queries
- Work offline for previously queried text

## Requirements

- KOReader version 2020.03 or later
- Internet connection for API calls
- OpenRouter API key

## License

MIT License