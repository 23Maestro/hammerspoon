import { ActionPanel, List, Action, getPreferenceValues, closeMainWindow } from '@raycast/api'
import { runAppleScript, showFailureToast, useCachedPromise } from '@raycast/utils'

interface ScriptItem {
  id: string
  name: string
  description?: string
  keywords?: string[]
  group?: string
}

interface ScriptGroup {
  id: string
  title: string
  icon: string
  keywords: string[]
  matches: (item: ScriptItem) => boolean
}

const SCRIPT_GROUPS: ScriptGroup[] = [
  {
    id: 'job-filling',
    title: 'Job Filling',
    icon: '💼',
    keywords: ['job', 'work', 'history', 'education', 'application', 'career'],
    matches: (item) => item.group === 'Job Filling' || item.id.startsWith('job-form.')
  },
  {
    id: 'chrome',
    title: 'Chrome',
    icon: '🌐',
    keywords: ['chrome', 'browser', 'selector', 'save'],
    matches: (item) => item.group === 'Chrome' || item.id.startsWith('chrome.')
  },
  {
    id: 'saved-browser-actions',
    title: 'Saved Browser Actions',
    icon: '🔗',
    keywords: ['saved', 'browser', 'element'],
    matches: (item) => item.group === 'Saved Browser Actions'
  },
  {
    id: 'local-actions',
    title: 'Local Actions',
    icon: '🖥️',
    keywords: ['local', 'app', 'accessibility', 'element'],
    matches: (item) => item.group === 'Local Actions' || item.id.startsWith('local.')
  },
  {
    id: 'Diagnostics',
    title: 'Diagnostics',
    icon: '🩺',
    keywords: ['automation', 'health', 'debug'],
    matches: (item) => item.group === 'Diagnostics' || item.id.startsWith('automation.')
  }
]

export default function main() {
  const {
    isLoading,
    data: scriptItems,
    revalidate: revalidateScripts,
    error
  } = useCachedPromise(
    async (): Promise<ScriptItem[]> => {
      const preferences = getPreferenceValues()
      const output = await runAppleScript(
        `
        ;(() => {
          const app = Application('Hammerspoon')
          const output = app.executeLuaCode(\`
            if ${preferences.scriptsVariableName} and type(${preferences.scriptsVariableName}.list) == 'function' then
              return ${preferences.scriptsVariableName}.list()
            end

            return hs.json.encode({ error = "Could not find scripts variable '${
              preferences.scriptsVariableName
            }' or it does not have a .list function. Make sure it exists in your Hammerspoon configuration file or that it is a valid object with functions" })
          \`)
          return output
        })()
      `,
        { language: 'JavaScript' }
      )

      const parsed = JSON.parse(output)

      if (parsed.error) {
        throw new Error(parsed.error)
      }

      const baseErrMsg = `"${preferences.scriptsVariableName}.list()" returned invalid output.`

      if (!Array.isArray(parsed)) {
        throw new Error(`${baseErrMsg} It should return an array of script objects.`)
      }

      for (const script of parsed) {
        if (typeof script.id !== 'string' || typeof script.name !== 'string') {
          throw new Error(`${baseErrMsg} Each script object should have at least an .id and .name property.`)
        }

        if (script.id.trim() === '' || script.name.trim() === '') {
          throw new Error(`${baseErrMsg} Each script object should have a non-empty .id and .name property.`)
        }
      }

      const scripts = parsed as ScriptItem[]
      return scripts
    },
    [],
    {
      initialData: [],
      failureToastOptions: {
        title: "Couldn't resolve user scripts of Hammerspoon"
      }
    }
  )

  let targetScripts: ScriptItem[] = scriptItems

  if (error) {
    targetScripts = []
  }

  return (
    <List isLoading={isLoading} searchBarPlaceholder="Type to search...">
      <List.Section title="Groups">{renderGroupItems(targetScripts, revalidateScripts)}</List.Section>
    </List>
  )
}

function renderGroupItems(items: ScriptItem[], revalidateScripts: () => void) {
  const groupedItemIds = new Set<string>()

  const groups = SCRIPT_GROUPS.map((group) => {
    const groupItems = items.filter(group.matches)
    groupItems.forEach((item) => groupedItemIds.add(item.id))
    return { ...group, items: groupItems }
  }).filter((group) => group.items.length > 0)

  const otherItems = items.filter((item) => !groupedItemIds.has(item.id))
  if (otherItems.length > 0) {
    groups.push({
      id: 'other',
      title: 'Other',
      icon: '📄',
      keywords: ['other', 'scripts'],
      matches: () => false,
      items: otherItems
    })
  }

  return groups.map((group) => (
    <List.Item
      key={group.id}
      icon={group.icon}
      title={group.title}
      accessories={[{ text: 'Group' }]}
      keywords={[...group.keywords, ...group.items.flatMap((item) => [item.name, ...(item.keywords ?? [])])]}
      actions={
        <ActionPanel>
          <Action.Push
            title="Open Group"
            icon="↩️"
            target={<ScriptGroupView title={group.title} items={group.items} revalidateScripts={revalidateScripts} />}
          />
          <Action title="Refresh" onAction={revalidateScripts} shortcut={{ modifiers: ['cmd'], key: 'r' }} icon="🔄" />
        </ActionPanel>
      }
    />
  ))
}

function ScriptGroupView({
  title,
  items,
  revalidateScripts
}: {
  title: string
  items: ScriptItem[]
  revalidateScripts: () => void
}) {
  return (
    <List navigationTitle={title} searchBarPlaceholder="Type to search...">
      <List.Section title={title}>{renderListItems(items, revalidateScripts)}</List.Section>
    </List>
  )
}

function renderListItems(items: ScriptItem[], revalidateScripts: () => void) {
  return items.map((item) => {
    return (
      <List.Item
        key={item.id}
        icon="⚡️"
        title={item.name}
        keywords={item.keywords ?? []}
        subtitle={{ value: item.description, tooltip: item.description }}
        actions={
          <ActionPanel>
            <Action
              title="Execute Script"
              icon="▶️"
              onAction={async () => {
                const preferences = getPreferenceValues()

                // NOTE: we sanitize the script id to avoid Lua syntax errors caused by double-quotes or escape sensitive characters
                try {
                  const output = await runAppleScript(
                    `
                    ;(() => {
                      const app = Application('Hammerspoon')
                      const output = app.executeLuaCode(\`
                        local ok, sanitizedId = pcall(function() return hs.json.decode('${JSON.stringify(item.id)}') end)

                        if not ok then
                          return hs.json.encode({ error = "Failed to decode script id" })
                        end

                        if ${preferences.scriptsVariableName} and type(${preferences.scriptsVariableName}.execute) == 'function' then
                          return ${preferences.scriptsVariableName}.execute(sanitizedId)
                        end

                        return hs.json.encode({ error = "Could not find scripts variable '${
                          preferences.scriptsVariableName
                        }' or it does not have a .execute function. Make sure it exists in your Hammerspoon configuration file or that it is a valid object with functions" })
                      \`)
                      return output
                    })()
                  `,
                    { language: 'JavaScript' }
                  )

                  if (output !== '') {
                    let parsed
                    try {
                      parsed = JSON.parse(output)
                    } catch {
                      throw new Error(output)
                    }

                    if (parsed.error) {
                      throw new Error(parsed.error)
                    }
                  }
                } catch (error) {
                  await showFailureToast(error, { title: 'Script Execution Failed' })
                  return
                }

                await closeMainWindow({ clearRootSearch: true })
              }}
            />
            <Action
              title="Refresh"
              onAction={revalidateScripts}
              shortcut={{ modifiers: ['cmd'], key: 'r' }}
              icon="🔄"
            />
          </ActionPanel>
        }
      />
    )
  })
}
