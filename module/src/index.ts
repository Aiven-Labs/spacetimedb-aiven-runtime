// Example module: replace with your own. It shows the three things most deployments need.
//
//  1. A public table clients can subscribe to, written only through a reducer.
//  2. An owner-only reducer for configuration, so secrets arrive at runtime (via the
//     container's POST_PUBLISH_CALLS) instead of being baked into the image.
//  3. `init` recording who published, which is how a module knows who "the owner" is.
import { schema, table, t, SenderError } from 'spacetimedb/server';

const counter = table({ name: 'counter', public: true }, {
  id: t.u32().primaryKey(),
  count: t.u64(),
});

// Private (no `public: true`): clients cannot read it, reducers can.
const admin = table({ name: 'admin' }, { id: t.u32().primaryKey(), owner: t.identity() });
const settings = table({ name: 'settings' }, { id: t.u32().primaryKey(), greeting: t.string() });

const spacetimedb = schema({ counter, admin, settings });
export default spacetimedb;

export const init = spacetimedb.init((ctx) => {
  ctx.db.admin.insert({ id: 0, owner: ctx.sender });
  ctx.db.counter.insert({ id: 0, count: 0n });
});

export const ping = spacetimedb.reducer((ctx) => {
  const row = ctx.db.counter.id.find(0);
  if (row) ctx.db.counter.id.update({ ...row, count: row.count + 1n });
});

// Only the publisher (the container's CLI identity) may call this.
export const setGreeting = spacetimedb.reducer({ greeting: t.string() }, (ctx, { greeting }) => {
  const a = ctx.db.admin.id.find(0);
  if (!a || !a.owner.equals(ctx.sender)) throw new SenderError('not the database owner');
  const row = { id: 0, greeting };
  if (ctx.db.settings.id.find(0)) ctx.db.settings.id.update(row);
  else ctx.db.settings.insert(row);
});
