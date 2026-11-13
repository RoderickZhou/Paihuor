function household(db, { isRole, isFamily, isUuid, transaction }) {
  db.exec(`CREATE TABLE IF NOT EXISTS household_cards (
    id TEXT PRIMARY KEY, familyId TEXT NOT NULL, list TEXT NOT NULL, title TEXT NOT NULL,
    detail TEXT NOT NULL, images TEXT NOT NULL, creator TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'available', assignee TEXT NOT NULL DEFAULT '',
    createdAt INTEGER NOT NULL, doneAt INTEGER NOT NULL DEFAULT 0, revision INTEGER NOT NULL DEFAULT 0,
    deleted INTEGER NOT NULL DEFAULT 0
  ); CREATE INDEX IF NOT EXISTS idx_household_family ON household_cards(familyId,createdAt);`);
  if (!db.prepare('PRAGMA table_info(household_cards)').all().some(column => column.name === 'deleted')) {
    db.exec('ALTER TABLE household_cards ADD COLUMN deleted INTEGER NOT NULL DEFAULT 0');
  }
  const find = db.prepare('SELECT * FROM household_cards WHERE familyId=? AND id=?');
  const read = row => ({ ...row, images: JSON.parse(row.images) });
  const list = db.prepare('SELECT * FROM household_cards WHERE familyId=? AND deleted=0 ORDER BY createdAt DESC,rowid ASC');
  const insert = db.prepare(`INSERT INTO household_cards (id,familyId,list,title,detail,images,creator,createdAt)
    VALUES (?,?,?,?,?,?,?,?) ON CONFLICT(id) DO NOTHING`);
  const set = db.prepare('UPDATE household_cards SET status=?,assignee=?,doneAt=?,revision=revision+1 WHERE familyId=? AND id=? AND revision=?');
  const edit = db.prepare('UPDATE household_cards SET title=?,detail=?,list=?,revision=revision+1 WHERE familyId=? AND id=? AND revision=?');
  const remove = db.prepare("UPDATE household_cards SET deleted=1,images='[]',title='',detail='',list='',revision=revision+1 WHERE familyId=? AND id=? AND revision=?");
  const attachment = db.prepare('SELECT id,mime,w,h,size FROM attachments WHERE id=? AND familyId=?');
  const clean = (value, max) => typeof value === 'string' && value.trim().length <= max ? value.trim() : null;
  const error = (status, message) => [status, { error: message }];

  return {
    list(family) {
      return isFamily(family) ? [200, list.all(family).map(read)] : error(400, 'invalid family');
    },
    create(body) {
      const { familyId, userId, items } = body || {};
      const name = clean(body?.list ?? '', 40);
      if (!isFamily(familyId) || !isRole(userId) || name === null || !Array.isArray(items) || items.length < 1 || items.length > 50) {
        return error(400, 'invalid card batch');
      }
      const prepared = [];
      for (const item of items) {
        const title = clean(item?.title, 120);
        const detail = clean(item?.detail ?? '', 2000);
        const ids = item?.imageIds ?? [];
        if (!isUuid(item?.id) || !title || detail === null || !Array.isArray(ids) || ids.length > 9 || !ids.every(isUuid)) {
          return error(400, 'invalid card');
        }
        const images = [...new Set(ids)].map(id => attachment.get(id, familyId));
        if (images.some(image => !image)) return error(400, 'attachment not found in family');
        prepared.push({ id: item.id, title, detail, images });
      }
      const now = Date.now();
      transaction(() => {
        for (const item of prepared) insert.run(item.id, familyId, name || '日常', item.title, item.detail,
          JSON.stringify(item.images), userId, now);
      });
      return [200, { ok: true }];
    },
    act(id, body) {
      const { familyId, userId, action, revision } = body || {};
      if (!isUuid(id) || !isFamily(familyId) || !isRole(userId) || !Number.isInteger(revision)
        || !['claim', 'release', 'complete', 'edit', 'delete', 'reopen'].includes(action)) return error(400, 'invalid card action');
      const card = find.get(familyId, id);
      if (!card || card.deleted) return error(404, 'card not found');
      if (card.revision !== revision) return error(409, 'card changed');
      if (action === 'edit' || action === 'delete') {
        if (card.creator !== userId && !(action === 'edit' && card.assignee === userId)) return error(403, 'not allowed');
        if (action === 'delete') {
          remove.run(familyId, id, revision);
          return [200, { ok: true }];
        }
        const title = clean(body.title, 120), detail = clean(body.detail, 2000), name = clean(body.list, 40);
        if (!title || detail === null || name === null) return error(400, 'invalid card fields');
        edit.run(title, detail, name || '日常', familyId, id, revision);
      } else if (action === 'reopen') {
        if (card.status !== 'done') return error(409, 'card no longer completed');
        if (card.assignee !== userId) return error(403, 'only the assignee can do this');
        set.run('claimed', userId, 0, familyId, id, revision);
      } else if (action === 'claim') {
        if (card.status !== 'available') return error(409, 'card no longer available');
        set.run('claimed', userId, 0, familyId, id, revision);
      } else {
        if (card.status !== 'claimed') return error(409, 'card no longer in progress');
        if (card.assignee !== userId) return error(403, 'only the assignee can do this');
        if (action === 'release') set.run('available', '', 0, familyId, id, revision);
        else set.run('done', userId, Date.now(), familyId, id, revision);
      }
      return [200, read(find.get(familyId, id))];
    }
  };
}

module.exports = household;
