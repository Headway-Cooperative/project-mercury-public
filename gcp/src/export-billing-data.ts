import moment from 'moment'
import { BigQuery, Job, RowMetadata } from '@google-cloud/bigquery'
import * as ff from '@google-cloud/functions-framework'

ff.http('exportData', async (req: ff.Request, res: ff.Response) => {
  const start = moment.utc().startOf('day').subtract({ days: 2 }).toDate()
  const end = moment.utc().startOf('day').toDate()
  console.info(req.body)
  const { projectId, tableName } = req.body
  const tagNames = req.body.tagNames ? req.body.tagNames.split(',') : []
  const usage = await getUsage(
    start,
    end,
    projectId,
    tableName,
    tagNames
  )
  console.info(`retrieved ${usage.length} usage rows`)
  res.status(200).send()
})

/* Note about resource tags:
 * GCP supports three methods for labeling resources: tags (organization-level), project labels (project-level), and normal labels (resource-level).
 * We support all three under one config with the use of prefixes to specify the type of label that a key corresponds to.
 * The resulting key/value pairs are then merged into a single "tag" property for each resource.
 */
const getUsage = async (
  start: Date,
  end: Date,
  projectId: string,
  tableName: string,
  tagNames: string[],
): Promise<RowMetadata[]> => {
  const [tags, labels, projectLabels] = tagNamesToQueryColumns(tagNames)

  const [tagPropertySelections, tagPropertyJoins] = buildTagQuery(
    'tags',
    tags,
  )
  const [labelPropertySelections, labelPropertyJoins] = buildTagQuery(
    'labels',
    labels,
  )
  const [projectLabelPropertySelections, projectLabelPropertyJoins] = buildTagQuery('projectLabels', projectLabels)

  const query = `SELECT
                    DATE(usage_start_time) as timestamp,
                    project.id as accountId,
                    project.name as accountName,
                    ifnull(location.region, location.location) as region,
                    service.description as serviceName,
                    sku.description as usageType,
                    usage.unit as usageUnit,
                    system_labels.value AS machineType,
                    SUM(usage.amount) AS usageAmount,
                    SUM(cost) AS cost
                    ${tagPropertySelections}
                    ${labelPropertySelections}
                    ${projectLabelPropertySelections}
                  FROM
                    \`${tableName}\`
                  LEFT JOIN
                    UNNEST(system_labels) AS system_labels
                    ON system_labels.key = "compute.googleapis.com/machine_spec"
                  ${tagPropertyJoins}
                  ${labelPropertyJoins}
                  ${projectLabelPropertyJoins}
                  WHERE
                    cost_type != 'rounding_error'
                    AND usage.unit IN ('byte-seconds', 'seconds', 'bytes', 'requests')
                    AND usage_start_time BETWEEN TIMESTAMP('${moment
      .utc(start)
      .format('YYYY-MM-DDTHH:mm:ssZ')}') AND TIMESTAMP('${moment
        .utc(end)
        .format('YYYY-MM-DDTHH:mm:ssZ')}')
                  GROUP BY
                    timestamp,
                    accountId,
                    accountName,
                    region,
                    serviceName,
                    usageType,
                    usageUnit,
                    machineType`

  const bigQuery = new BigQuery({ projectId })
  console.info(query)
  let job: Job
    ;[job] = await bigQuery.createQueryJob({ query })
  let rows: RowMetadata
    ;[rows] = await job.getQueryResults()
  return rows
}

const tagNamesToQueryColumns = (tagNames: string[]): string[][] => {
  const tagColumns: { [column: string]: string[] } = {
    tag: [],
    project: [],
    label: [],
  }

  // For each string in tag label, check the colon-separated prefix to determine which type of label it is
  tagNames.forEach((tag) => {
    const [prefix, key] = tag.split(':')
    const column = tagColumns[prefix]
    if (column) {
      column.push(key)
    } else {
      console.warn(
        `Unknown tag prefix: ${prefix}. Ignoring tag: ${tag}`,
      )
    }
  })

  return Object.values(tagColumns)
}

const buildTagQuery = (columnName: string, keys: string[]): string[] => {
  let propertySelections = '',
    propertyJoins = ''

  if (keys.length > 0) {
    propertySelections = `, STRING_AGG(DISTINCT CONCAT(${columnName}.key, ": ", ${columnName}.value), ", ") AS ${columnName}`

    propertyJoins = `\nLEFT JOIN\n UNNEST(${columnName === 'projectLabels' ? 'project.label' : columnName
      }) AS ${columnName}\n`
    propertyJoins += keys.map((tag) => `ON tags.key = "${tag}"`).join(' OR ')
  }
  return [propertySelections, propertyJoins]
}