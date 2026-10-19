import fs from 'node:fs';
import path from 'node:path';
import type {SidebarsConfig} from '@docusaurus/plugin-content-docs';
import deviceApi from './docs/reference/api/device/sidebar';
import e2eApi from './docs/reference/api/e2e/sidebar';
import reportApi from './docs/reference/api/report/sidebar';
import {deliveredFeatures} from './src/features';

type SidebarItemConfig = Extract<SidebarsConfig[string], unknown[]>[number];

const doc = (id: string, label: string): SidebarItemConfig => ({type: 'doc', id, label});

const category = (
  label: string,
  items: SidebarItemConfig[],
  options: {link?: string; collapsed?: boolean} = {},
): SidebarItemConfig => ({
  type: 'category',
  label,
  collapsed: options.collapsed ?? true,
  ...(options.link ? {link: {type: 'doc', id: options.link}} : {}),
  items,
});

// Wrap a generated OpenAPI sidebar in a category linked to its overview page.
// The specs define no tags, so the generator's single "UNTAGGED" group is flattened.
function apiCategory(label: string, items: SidebarItemConfig[]): SidebarItemConfig {
  const [overview, ...operations] = items as {type: string; id?: string; label?: string; items?: SidebarItemConfig[]}[];
  return {
    type: 'category',
    label,
    link: {type: 'doc', id: overview.id!},
    items: operations.flatMap((item) =>
      item.type === 'category' && item.label === 'UNTAGGED' ? item.items! : [item as SidebarItemConfig],
    ),
  };
}

// Like apiCategory, but linked to a hand-written page that replaces the generated overview.
function apiOperations(label: string, items: SidebarItemConfig[], link: string): SidebarItemConfig {
  const {items: operations} = apiCategory(label, items) as {items: SidebarItemConfig[]};
  return category(label, operations, {link});
}

// Implemented features are listed from their delivered records, so only completed work appears. A feature's design
// record is linked from its implemented record; any other pages in its directory nest under it.
function implementedFeatures(): SidebarItemConfig[] {
  return deliveredFeatures().map(({slug, title}) => {
    const extras = fs
      .readdirSync(path.join(__dirname, 'docs/features', slug))
      .filter((file) => /\.mdx?$/.test(file) && !['index.md', 'design.md'].includes(file))
      .map((file) => {
        const source = fs.readFileSync(path.join(__dirname, 'docs/features', slug, file), 'utf8');
        const heading = source.match(/^# (.+)$/m)?.[1] ?? file;
        return doc(`features/${slug}/${file.replace(/\.mdx?$/, '')}`, heading);
      });
    return extras.length
      ? category(title, extras, {link: `features/${slug}/index`})
      : doc(`features/${slug}/index`, title);
  });
}

// Navigation for website/docs, grouped by reader intent. Register every new durable page here.
const sidebars: SidebarsConfig = {
  docs: [
    doc('README', 'Introduction'),
    category(
      'Architecture',
      [
        doc('architecture', 'Architecture Overview'),
        doc('repository-structure', 'Project Structure'),
        doc('runtime-boundaries', 'Runtime Boundaries'),
        doc('data-flow', 'Data Flow'),
        category(
          'Module Reference',
          [
            doc('modules/server-application', 'Server Application'),
            doc('modules/server-domain', 'Server Domain'),
            doc('modules/server-web', 'Server Web'),
            doc('modules/server-devices', 'Server Devices'),
            doc('modules/server-provisioning', 'Server Provisioning'),
            doc('modules/server-monitoring', 'Server Monitoring'),
            doc('modules/server-scripts', 'Server Scripts'),
            doc('modules/server-reporting', 'Server Reporting'),
            doc('modules/client-cli', 'Client CLI'),
            doc('modules/client-transport', 'Client Transport'),
            doc('modules/client-identity', 'Client Identity'),
            doc('modules/client-starlark-runtime', 'Client Starlark Runtime'),
            doc('modules/client-command-handler', 'Client Command Handler'),
            doc('modules/client-frp-manager', 'Client FRP Manager'),
            doc('modules/gateway-caddy', 'Gateway Caddy'),
            doc('modules/gateway-frp', 'Gateway FRP'),
          ],
          {link: 'modules/index'},
        ),
      ],
      {collapsed: false},
    ),
    category('Operations', [
      doc('operations/deployment', 'Deployment'),
      doc('operations/client-installation', 'Client Installation'),
      doc('operations/backup-restore', 'Backup And Restore'),
      doc('operations/secret-rotation', 'Secret Rotation'),
      doc('operations/health-checks', 'Health Checks'),
      doc('operations/device-groups', 'Device Groups'),
      doc('operations/command-policies', 'Command Policies'),
      doc('operations/script-workbench', 'Stary Script Workbench'),
      doc('operations/incidents', 'Incident Response'),
      doc('operations/upgrades-rollbacks', 'Upgrades And Rollbacks'),
      doc('operations/ha-scaling', 'HA And Scaling'),
    ], {link: 'operations/index'}),
    category(
      'Development',
      [
        doc('development/tooling', 'Developer Tooling'),
        doc('development/tooling-reference', 'Tooling Reference'),
        doc('development/local-stack', 'Local Stack'),
        doc('development/feature-lifecycle', 'Feature Lifecycle'),
        doc('development/documentation-conventions', 'Documentation Conventions'),
        category('E2E Testing', [
          doc('development/e2e/client-harness', 'Client E2E Harness'),
          doc('development/e2e/server', 'Server E2E'),
          apiOperations('E2E API', e2eApi, 'development/e2e/api'),
          doc('development/e2e/results', 'E2E Results'),
        ]),
        doc('development/releasing', 'Releasing'),
        doc('development/github-pages', 'GitHub Pages Deployment'),
      ],
      {link: 'development', collapsed: false},
    ),
    category(
      'Reference',
      [
        doc('reference/deployment-configuration', 'Deployment Configuration'),
        category(
          'API & Runtime Contracts',
          [
            category(
              'OpenAPI Contracts',
              [
                apiCategory('Device API', deviceApi),
                apiCategory('Report API', reportApi),
              ],
              {link: 'reference/openapi/index'},
            ),
          ],
          {link: 'reference/contracts'},
        ),
        doc('client-server-interface', 'Client-Server Interface'),
      ],
      {collapsed: false},
    ),
    category('Implemented Features', implementedFeatures(), {link: 'features/index'}),
  ],
};

export default sidebars;
