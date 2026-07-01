import { test, expect, Page } from '@playwright/test';
import path from 'path';

const LLM_PROVIDER = (process.env.LLM_PROVIDER || 'ollama').toLowerCase();
const LLM_API_KEY = process.env.LLM_API_KEY || '';
const LLM_BASE_URL = process.env.LLM_BASE_URL || '';
const LLM_MODEL = process.env.LLM_MODEL || (LLM_PROVIDER === 'ollama' ? 'llava' : 'gpt-4o-mini');
const OLLAMA_BASE_URL = process.env.OLLAMA_BASE_URL || 'http://localhost:11434/v1/chat/completions';
const OLLAMA_MODEL = process.env.OLLAMA_MODEL || 'llava';

const REAL_LLM =
  process.env.FORCE_LLM_TESTS === 'true' ||
  (LLM_PROVIDER !== 'none' &&
    (LLM_PROVIDER === 'ollama'
      ? !!process.env.OLLAMA_BASE_URL
      : LLM_API_KEY.length > 0));
// When no real LLM is available, mock the OpenAI-compatible completions endpoint
// so the text-search and image-analysis code paths are still exercised E2E.
const USE_MOCK_LLM = !REAL_LLM;
const HAS_LLM = REAL_LLM || USE_MOCK_LLM;

const PROVIDER_LABEL: Record<string, string> = {
  ollama: 'Ollama',
  openrouter: 'OpenRouter',
  openai: 'OpenAI',
  none: 'None',
};

const LLM_BASE_URL_VALUE = LLM_PROVIDER === 'ollama' ? OLLAMA_BASE_URL : LLM_BASE_URL;
const LLM_MODEL_VALUE = LLM_PROVIDER === 'ollama' ? OLLAMA_MODEL : LLM_MODEL;

test.describe.configure({ mode: 'serial' });

const byLabel = (label: string) => `flt-semantics[aria-label*="${label}"]`;

async function fillField(page: Page, name: string, value: string) {
  const field = page.getByRole('textbox', { name });
  await expect(field).toBeVisible();
  await field.click();
  // Flutter web text fields occasionally drop the first keystrokes if typed
  // immediately after focus, so give the input a moment to settle.
  await page.waitForTimeout(200);
  await field.fill(value);
}

test.beforeEach(async ({ page }) => {
  // Playwright treats '/' as the origin root, so use '' to land on baseURL.
  await page.goto('');
  await page.waitForLoadState('networkidle');

  if (USE_MOCK_LLM) {
    await page.route('**/v1/chat/completions', async (route, request) => {
      const body = request.postDataJSON() ?? {};
      const hasImage = JSON.stringify(body).includes('image_url');
      const content = hasImage
        ? '{"description": "a sample screenshot", "tags": ["sample", "screenshot"]}'
        : '{"area": "development", "topics": ["flutter-state-management"], "tags": ["flutter", "state-management"], "questions": [{"id": "q_1", "author": "", "text": "How do I manage state in Flutter?", "date": "", "area": "development", "topics": [], "tags": [], "answeredBy": "a_1", "links": []}], "answers": [{"id": "a_1", "author": "", "text": "Use a state management solution like Riverpod or Bloc.", "date": "", "area": "development", "topics": [], "tags": [], "answersQuestion": "q_1", "quality": 0.9, "links": []}], "notes": [{"id": "n_1", "author": "", "text": "State management is important for scalable Flutter apps.", "date": "", "area": "development", "topics": [], "tags": [], "links": []}]}';
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          id: 'mock',
          object: 'chat.completion',
          choices: [
            {
              index: 0,
              message: { role: 'assistant', content },
              finish_reason: 'stop',
            },
          ],
        }),
      });
    });
  }

  await page.evaluate(() => localStorage.clear());
  await page.reload();
  await page.waitForLoadState('networkidle');
  await expect(page.locator(byLabel('Empty state')).first()).toBeVisible();
});

test('adds and shows text records', async ({ page }) => {
  await page.getByRole('button', { name: 'Add first record' }).click();
  await expect(page.getByText('Add record')).toBeVisible();

  await fillField(page, 'Text', 'What is Dart?');
  await fillField(page, 'Area', 'dart');
  await fillField(page, 'Tags (comma separated)', 'dart, programming');
  await page.getByRole('button', { name: 'Add' }).click();

  await expect(page.locator(byLabel('What is Dart?')).first()).toBeVisible();

  await page.getByRole('button', { name: 'Add record' }).click();
  await page.getByRole('button', { name: 'Note' }).click();
  await fillField(page, 'Text', 'Dart is a client-optimized language.');
  await fillField(page, 'Area', 'dart');
  await fillField(page, 'Tags (comma separated)', 'dart, language');
  await page.getByRole('button', { name: 'Add' }).click();

  await expect(page.locator(byLabel('Dart is a client-optimized language.')).first()).toBeVisible();
});

test('searches by tags', async ({ page }) => {
  await page.getByRole('button', { name: 'Add first record' }).click();
  await fillField(page, 'Text', 'Flutter state management');
  await fillField(page, 'Tags (comma separated)', 'flutter, state');
  await page.getByRole('button', { name: 'Add' }).click();
  await expect(page.locator(byLabel('Flutter state management')).first()).toBeVisible();

  await page.getByRole('tab', { name: 'Search' }).click();
  await fillField(page, 'Search by tags', 'flutter');
  await page.keyboard.press('Enter');

  await expect(page.locator(byLabel('Flutter state management')).first()).toBeVisible();
});

test('configures LLM provider and searches by text', async ({ page }) => {
  test.skip(!HAS_LLM, 'Set LLM_PROVIDER + LLM_API_KEY or OLLAMA_BASE_URL to run LLM-backed tests');

  await page.getByRole('tab', { name: 'Settings' }).click();
  await page.getByRole('checkbox', { name: PROVIDER_LABEL[LLM_PROVIDER] }).click();
  if (LLM_API_KEY) {
    await fillField(page, /API key|token/i, LLM_API_KEY);
  }
  if (LLM_BASE_URL_VALUE) {
    await fillField(page, 'Base URL (optional)', LLM_BASE_URL_VALUE);
  }
  await fillField(page, 'Model', LLM_MODEL_VALUE);
  await page.getByRole('button', { name: 'Save settings' }).click();

  await expect(page.getByText(/LLM ready\s*yes/)).toBeVisible();

  await page.getByRole('tab', { name: 'Records' }).click();
  await page.getByRole('button', { name: 'Add record' }).click();
  await fillField(page, 'Text', 'How do I manage state in Flutter?');
  await fillField(page, 'Tags (comma separated)', 'flutter');
  await page.getByRole('button', { name: 'Add' }).click();
  await expect(page.locator(byLabel('How do I manage state in Flutter?')).first()).toBeVisible();

  await page.getByRole('tab', { name: 'Search' }).click();
  await page.getByRole('button', { name: 'By text' }).first().click();
  await fillField(page, 'Search by text', 'state management');
  await page.keyboard.press('Enter');

  await expect(page.locator(byLabel('How do I manage state in Flutter?')).first()).toBeVisible({ timeout: 60000 });
});

test('builds graph', async ({ page }) => {
  await page.getByRole('button', { name: 'Add first record' }).click();
  await fillField(page, 'Text', 'Graph node A');
  await page.getByRole('button', { name: 'Add' }).click();
  await expect(page.locator(byLabel('Graph node A')).first()).toBeVisible();

  await page.getByRole('tab', { name: 'Graph' }).click();
  await expect(page.getByText(/Nodes\s*\d+/)).toBeVisible();
  await expect(page.getByText(/Edges\s*\d+/)).toBeVisible();
});

test('decomposes raw text into questions, answers and notes', async ({ page }) => {
  await page.getByRole('button', { name: 'Add first record' }).click();
  await page.getByRole('button', { name: 'Raw text' }).click();
  await fillField(
    page,
    'Paste raw text here',
    'We need to pick a state management approach for the Flutter app. How do I manage state in Flutter? Use a state management solution like Riverpod or Bloc. State management is important for scalable Flutter apps.',
  );
  await page.getByRole('button', { name: 'Add' }).click();

  // The dialog closes and at least one decomposed record appears.
  await expect(page.getByRole('button', { name: 'Add record' })).toBeVisible({ timeout: 120000 });
  await expect(page.locator(byLabel('Empty state')).first()).not.toBeVisible();

  if (USE_MOCK_LLM) {
    // With deterministic mocks we can assert exact decomposed entities.
    await expect(page.locator(byLabel('How do I manage state in Flutter?')).first()).toBeVisible();
    await expect(page.locator(byLabel('Use a state management solution like Riverpod or Bloc.')).first()).toBeVisible();
    await expect(page.locator(byLabel('State management is important for scalable Flutter apps.')).first()).toBeVisible();
  }
});

test('uploads and analyzes an image', async ({ page }) => {
  test.skip(!HAS_LLM, 'Set LLM_PROVIDER + LLM_API_KEY or OLLAMA_BASE_URL to run LLM-backed image tests');

  await page.getByRole('tab', { name: 'Settings' }).click();
  await page.getByRole('checkbox', { name: PROVIDER_LABEL[LLM_PROVIDER] }).click();
  if (LLM_API_KEY) {
    await fillField(page, /API key|token/i, LLM_API_KEY);
  }
  if (LLM_BASE_URL_VALUE) {
    await fillField(page, 'Base URL (optional)', LLM_BASE_URL_VALUE);
  }
  await fillField(page, 'Model', LLM_MODEL_VALUE);
  await page.getByRole('button', { name: 'Save settings' }).click();
  await expect(page.getByText(/LLM ready\s*yes/)).toBeVisible();

  await page.getByRole('tab', { name: 'Records' }).click();
  await page.getByRole('button', { name: 'Add record' }).click();

  await page.getByRole('button', { name: 'Image' }).click();

  const fileChooserPromise = page.waitForEvent('filechooser');
  await page.getByRole('button', { name: 'Pick image' }).click();
  const fileChooser = await fileChooserPromise;
  await fileChooser.setFiles(path.join(__dirname, '../fixtures/sample.png'));

  await page.getByRole('button', { name: 'Add' }).click();

  await expect(page.locator(byLabel('Image analysis:')).first()).toBeVisible({ timeout: 120000 });
});
