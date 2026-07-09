import { Action, ActionPanel, Clipboard, Form, Icon, popToRoot, showToast, Toast } from '@raycast/api'
import { FormValidation, runAppleScript, showFailureToast } from '@raycast/utils'
import { readFileSync } from 'node:fs'
import { mkdir, readFile, writeFile } from 'node:fs/promises'
import { homedir } from 'node:os'
import { dirname, join } from 'node:path'
import { useMemo, useState } from 'react'

const browserLatestElementPath = join(homedir(), '.hammerspoon', 'browser_element_latest.json')
const localLatestElementPath = join(homedir(), '.hammerspoon', 'local_element_latest.json')
const actionsPath = join(homedir(), '.hammerspoon', 'browser_element_actions.json')

type ActionVariant = 'browser' | 'local'
type ActionTemplate = 'one-click' | 'two-click'

interface ElementPayload {
  kind?: string
  captureMethod?: string
  selector?: string
  url?: string
  title?: string
  text?: string
  tag?: string
  id?: string
  className?: string
  appName?: string
  appPath?: string
  bundleID?: string
  windowTitle?: string
  role?: string
  subrole?: string
  axTitle?: string
  axValue?: string
  axDescription?: string
}

interface ElementAction {
  id: string
  name: string
  variant?: ActionVariant
  template: ActionTemplate
  selector?: string
  urlIncludes?: string
  titleIncludes?: string
  requiredSelector?: string
  appBundleID?: string
  appName?: string
  appPath?: string
  windowTitleIncludes?: string
  axRole?: string
  axTitle?: string
  axValue?: string
  axDescription?: string
  hotkey?: {
    modifiers: string[]
    key: string
  }
}

interface FormValues {
  variant: ActionVariant
  name: string
  template: ActionTemplate
  selector: string
  urlIncludes: string
  titleIncludes: string
  requiredSelector: string
  appBundleID: string
  appName: string
  appPath: string
  windowTitleIncludes: string
  axRole: string
  axTitle: string
  axValue: string
  axDescription: string
  hotkey: string
}

const emptyValues: FormValues = {
  variant: 'browser',
  name: '',
  template: 'one-click',
  selector: '',
  urlIncludes: '',
  titleIncludes: '',
  requiredSelector: '',
  appBundleID: '',
  appName: '',
  appPath: '',
  windowTitleIncludes: '',
  axRole: '',
  axTitle: '',
  axValue: '',
  axDescription: '',
  hotkey: ''
}

export default function Command() {
  const browserElement = loadElementSync(browserLatestElementPath, 'hammerspoon-browser-element')
  const localElement = loadElementSync(localLatestElementPath, 'hammerspoon-local-element')
  const initialValues = useMemo(() => valuesFromElement(browserElement, 'browser'), [])
  const [values, setValues] = useState<FormValues>(initialValues)

  async function submit() {
    const validationError = validate(values)
    if (validationError) {
      await showToast({ style: Toast.Style.Failure, title: validationError })
      return
    }

    const action = buildAction(values)
    const actions = await readActions()
    const nextActions = [...actions.filter((item) => item.id !== action.id), action]

    await mkdir(dirname(actionsPath), { recursive: true })
    await writeFile(actionsPath, `${JSON.stringify(nextActions, null, 2)}\n`, 'utf8')

    await reloadHammerspoon()
    await showToast({ style: Toast.Style.Success, title: 'Saved' })
    await popToRoot({ clearSearchBar: true })
  }

  async function captureLocalElement() {
    try {
      const output = await runAppleScript(`
        tell application "Hammerspoon"
          execute lua code "return __SCRIPTS__.execute('local.capture-focused-element')"
        end tell
      `)
      const parsed = JSON.parse(output) as { status?: string; path?: string; error?: string }
      if (parsed.error || parsed.status !== 'captured-local-element') {
        throw new Error(parsed.error ?? parsed.status ?? 'Capture failed')
      }

      const element = loadElementSync(parsed.path ?? localLatestElementPath, 'hammerspoon-local-element')
      setValues(valuesFromElement(element, 'local', values.hotkey))
      await showToast({ style: Toast.Style.Success, title: 'Loaded Local Element' })
    } catch (error) {
      await showFailureToast(error, { title: 'Local Capture Failed' })
    }
  }

  async function loadLatestForVariant(variant = values.variant) {
    const element =
      variant === 'local'
        ? loadElementSync(localLatestElementPath, 'hammerspoon-local-element')
        : loadElementSync(browserLatestElementPath, 'hammerspoon-browser-element')

    setValues(valuesFromElement(element, variant, values.hotkey))
    await showToast({
      style: element ? Toast.Style.Success : Toast.Style.Failure,
      title: element ? 'Loaded Latest JSON' : 'No Latest JSON'
    })
  }

  async function loadClipboardJson() {
    try {
      const text = await Clipboard.readText()
      const parsed = JSON.parse(text ?? '') as ElementPayload
      const variant = variantFromPayload(parsed) ?? values.variant
      setValues(valuesFromElement(parsed, variant, values.hotkey))
      await showToast({ style: Toast.Style.Success, title: 'Loaded Clipboard JSON' })
    } catch (error) {
      await showFailureToast(error, { title: 'Clipboard JSON Failed' })
    }
  }

  return (
    <Form
      navigationTitle="Create Element Action"
      actions={
        <ActionPanel>
          <Action.SubmitForm title="Save Action" icon={Icon.SaveDocument} onSubmit={submit} />
          <ActionPanel.Section title="JSON">
            <Action title="Load Latest JSON" icon={Icon.Download} onAction={() => loadLatestForVariant()} />
            <Action title="Load JSON from Clipboard" icon={Icon.Clipboard} onAction={loadClipboardJson} />
            <Action.CopyToClipboard title="Copy Action JSON" content={JSON.stringify(buildAction(values), null, 2)} />
            <Action.CopyToClipboard
              title="Copy Latest JSON"
              content={JSON.stringify(values.variant === 'local' ? localElement : browserElement, null, 2)}
            />
          </ActionPanel.Section>
          <ActionPanel.Section title="Capture">
            <Action
              title="Use Browser Variant"
              icon={Icon.Globe}
              onAction={() => setValues(valuesFromElement(browserElement, 'browser', values.hotkey))}
            />
            <Action title="Capture Focused Local Element" icon={Icon.Desktop} onAction={captureLocalElement} />
            <Action
              title="Use Local Variant"
              icon={Icon.AppWindow}
              onAction={() => setValues(valuesFromElement(localElement, 'local', values.hotkey))}
            />
          </ActionPanel.Section>
        </ActionPanel>
      }
    >
      <Form.Dropdown
        id="variant"
        title="Target"
        value={values.variant}
        onChange={(variant) => {
          const nextVariant = variant as ActionVariant
          setValues(
            valuesFromElement(nextVariant === 'local' ? localElement : browserElement, nextVariant, values.hotkey)
          )
        }}
      >
        <Form.Dropdown.Item value="browser" title="Browser" />
        <Form.Dropdown.Item value="local" title="Local App" />
      </Form.Dropdown>
      <Form.TextField
        id="name"
        title="Name"
        autoFocus
        value={values.name}
        onChange={(name) => setValues({ ...values, name })}
      />
      <Form.Dropdown
        id="template"
        title="Type"
        value={values.template}
        onChange={(template) =>
          setValues({ ...values, template: template === 'two-click' ? 'two-click' : 'one-click' })
        }
      >
        <Form.Dropdown.Item value="one-click" title="Click Button" />
        <Form.Dropdown.Item value="two-click" title="Click Twice" />
      </Form.Dropdown>

      {values.variant === 'browser' ? (
        <Form.Description title="Captured Browser Target" text={latestSummary(browserElement)} />
      ) : (
        <Form.Description title="Captured Local Target" text={latestSummary(localElement)} />
      )}

      <Form.TextField
        id="hotkey"
        title="Hotkey"
        placeholder="ctrl+alt+j"
        value={values.hotkey}
        onChange={(hotkey) => setValues({ ...values, hotkey })}
      />
    </Form>
  )
}

function loadElementSync(path: string, kind: string): ElementPayload | undefined {
  try {
    const text = readFileSync(path, 'utf8')
    const parsed = JSON.parse(text) as ElementPayload
    return parsed.kind === kind ? parsed : undefined
  } catch {
    return undefined
  }
}

function variantFromPayload(element: ElementPayload | undefined): ActionVariant | undefined {
  if (element?.kind === 'hammerspoon-browser-element') {
    return 'browser'
  }

  if (element?.kind === 'hammerspoon-local-element') {
    return 'local'
  }

  return undefined
}

function valuesFromElement(element: ElementPayload | undefined, variant: ActionVariant, hotkey = ''): FormValues {
  return {
    ...emptyValues,
    variant,
    name: nameFromElement(element, variant),
    template: 'one-click',
    selector: element?.selector ?? '',
    urlIncludes: hostFromUrl(element?.url),
    titleIncludes: element?.title ?? '',
    appBundleID: element?.bundleID ?? '',
    appName: element?.appName ?? '',
    appPath: element?.appPath ?? '',
    windowTitleIncludes: element?.windowTitle ?? '',
    axRole: element?.role ?? '',
    axTitle: element?.axTitle ?? '',
    axValue: element?.axValue ?? '',
    axDescription: element?.axDescription ?? '',
    hotkey
  }
}

function nameFromElement(element: ElementPayload | undefined, variant: ActionVariant) {
  const text =
    element?.text?.trim() || element?.axTitle?.trim() || element?.axValue?.trim() || element?.axDescription?.trim()

  if (text) {
    return text.length > 32 ? text.slice(0, 32) : text
  }

  if (element?.id) {
    return element.id
  }

  if (element?.tag) {
    return `Click ${element.tag}`
  }

  if (element?.role) {
    return `Press ${element.role.replace(/^AX/, '')}`
  }

  return variant === 'local' ? 'Local App Action' : ''
}

function hostFromUrl(value: string | undefined) {
  if (!value) {
    return ''
  }

  try {
    return new URL(value).host
  } catch {
    return value
  }
}

function buildAction(values: FormValues): ElementAction {
  const hotkey = parseHotkey(values.hotkey)
  const base = {
    id: slug(values.name),
    name: values.name.trim(),
    variant: values.variant,
    template: values.template === 'two-click' ? 'two-click' : 'one-click',
    hotkey: hotkey ?? undefined
  }

  if (values.variant === 'local') {
    return {
      ...base,
      appBundleID: clean(values.appBundleID),
      appName: clean(values.appName),
      appPath: clean(values.appPath),
      windowTitleIncludes: clean(values.windowTitleIncludes),
      axRole: clean(values.axRole),
      axTitle: clean(values.axTitle),
      axValue: clean(values.axValue),
      axDescription: clean(values.axDescription)
    }
  }

  return {
    ...base,
    selector: values.selector.trim(),
    urlIncludes: clean(values.urlIncludes),
    titleIncludes: clean(values.titleIncludes),
    requiredSelector: clean(values.requiredSelector)
  }
}

function validate(values: FormValues) {
  if (FormValidation.Required(values.name)) {
    return 'Name is required'
  }

  if (values.variant === 'browser' && FormValidation.Required(values.selector)) {
    return 'Selector is required'
  }

  if (values.variant === 'local' && !values.axTitle && !values.axValue && !values.axDescription && !values.axRole) {
    return 'At least one AX field is required'
  }

  if (values.hotkey && !parseHotkey(values.hotkey)) {
    return 'Use ctrl+alt+x'
  }

  return undefined
}

async function readActions(): Promise<ElementAction[]> {
  try {
    const text = await readFile(actionsPath, 'utf8')
    const parsed = JSON.parse(text) as unknown
    return Array.isArray(parsed) ? (parsed as ElementAction[]) : []
  } catch {
    return []
  }
}

async function reloadHammerspoon() {
  try {
    await runAppleScript(`
      tell application "Hammerspoon"
        execute lua code "hs.reload()"
      end tell
    `)
  } catch (error) {
    await showFailureToast(error, { title: 'Reload failed' })
  }
}

function parseHotkey(value: string | undefined) {
  const normalized = value?.trim().toLowerCase()

  if (!normalized) {
    return undefined
  }

  const parts = normalized
    .split('+')
    .map((part) => part.trim())
    .filter(Boolean)
  const key = parts.at(-1)
  const modifiers = parts.slice(0, -1)
  const allowed = new Set(['cmd', 'ctrl', 'alt', 'shift'])

  if (!key || key.length === 0 || modifiers.length === 0 || modifiers.some((modifier) => !allowed.has(modifier))) {
    return undefined
  }

  return { modifiers, key }
}

function clean(value: string) {
  const trimmed = value.trim()
  return trimmed === '' ? undefined : trimmed
}

function slug(value: string) {
  return `element.${value
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-|-$/g, '')}`
}

function latestSummary(element: ElementPayload | undefined) {
  if (!element) {
    return 'No captured element found.'
  }

  return [
    element.text,
    element.axTitle,
    element.axValue,
    element.axDescription,
    element.tag ?? element.role,
    element.url ?? element.appName
  ]
    .filter(Boolean)
    .join(' · ')
}
