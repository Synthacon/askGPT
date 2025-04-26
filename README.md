# KOReader GPT Plugin

A plugin for KOReader that enhances your reading experience by adding AI capabilities through OpenRouter API integration. Select text from to get explanations, translations, summaries or custom prompt.


Created as a hobby, this project is still evolving, with 99% of the code written by AI.


☕ Buy me a coffe https://ko-fi.com/oneofusall

## Features

- Seamless integration with KOReader's text selection menu
- Support for multiple AI models through OpenRouter
- Shows pricing for each model ($/M input tokens $/M output tokens)
- Send custom prompt
- Translate selected text to any language
- Configurable system prompt
- Configurable translation prompt
- Ask follow-up guestions


## Installation

1. Create a folder named `askgpt.koplugin` in your KOReader plugins directory:
   ```
   /media/x/KOBOeReader/.adds/koreader/plugins/askgpt.koplugin
   ```

2. Copy all plugin files into the `askgpt.koplugin` directory

3. Restart KOReader

4. Configure the plugin:
   - Enable WIFI
   - Go to Settings -> More tools -> GPT Settings
   - Enter your OpenRouter API key
   - Select your preferred model


## Setting Up API Key and System Prompt

For the best experience, prepare these on your computer before configuring the plugin:

1. API Key Setup:
   - Create a text file on your computer
   - Save your OpenRouter API key in it
   - Transfer this file to your e-reader
   - Open the file and copy the API key
   - Paste it into the plugin's API key setting

2. System Prompt:
   - The Default system propt can be changed 
   - Create and edit your system prompt on your computer
   - Save it to a text file
   - Transfer to your e-reader
   - Copy and paste into the plugin's system prompt setting

This method is recommended as it's easier to edit and manage these settings on a computer rather than directly on the e-reader.

## Usage

1. Select any text in your book
2. Tap "Ask GPT" in the selection menu
3. Choose from four available tasks:
   - Explain: Get a clear explanation of the selected text
   - Summarize: Generate a concise summary
   - Translate: Convert text to any language (customizable)
   - Custom prompt
4. View the AI response
5. Ask follow-up questions

## Translation Feature

The plugin includes a translation task that can be customized to any target language. Simply specify your desired language when using the translate task (e.g., "Translate to Spanish" or "Translate to Japanese"). There are no language limitations - you can translate to any language. 

## Model Selection and Limitations

- Each model has different capabilities and pricing
- The quality and accuracy of responses depend on the selected model
- Important: ALL responses mirror the sophistication level of the chosen model
- Be aware that AI responses may be incorrect or imprecise. 

## Requirements

- Internet connection for API calls
- OpenRouter API key

## License

MIT License