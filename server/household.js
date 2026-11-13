function household(db, { isRole, isFamily, isUuid, transaction }) {
  db.exec(`CREATE TABLE IF NOT EXISTS household_cards (
    id TEXT PRIMARY KEY, familyId TEXT NOT NULL, list TEXT NOT NULL, title TEXT NOT NULL,
    detail TEXT NOT NULL, images TEXT NOT NULL, creator TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'available', assignee TEXT NOT NULL DEFAULT '',
    createdAt INTEGER NOT NULL, doneAt INTEGER NOT NULL DEFAULT 0, revision INTEGER NOT NULL DEFAULT 0,
    deleted INTEGER NOT NULL DEFAULT 0, deadline INTEGER NOT NULL DEFAULT 0,
    checklist TEXT NOT NULL DEFAULT '[]'
  ); CREATE INDEX IF NOT EXISTS idx_household_family ON household_cards(familyId,createdAt);`);
  const columns = new Set(db.prepare('PRAGMA table_info(household_cards)').all().map(column => column.name));
  for (const [name, type] of [['deleted', 'INTEGER NOT NULL DEFAULT 0'], ['deadline', 'INTEGER NOT NULL DEFAULT 0'],
    ['checklist', "TEXT NOT NULL DEFAULT '[]'"]]) {
    if (!columns.has(name)) db.exec(`ALTER TABLE household_cards ADD COLUMN ${name} ${type}`);
  }
  const find = db.prepare('SELECT * FROM household_cards WHERE familyId=? AND id=?');
  const read = row => ({ ...row, images: JSON.parse(row.images), checklist: JSON.parse(row.checklist) });
  const list = db.prepare('SELECT * FROM household_cards WHERE familyId=? AND deleted=0 ORDER BY createdAt DESC,rowid ASC');
  const insert = db.prepare(`INSERT INTO household_cards (id,familyId,list,title,detail,images,creator,createdAt,deadline,checklist)
    VALUES (?,?,?,?,?,?,?,?,?,?) ON CONFLICT(id) DO NOTHING`);
  const set = db.prepare('UPDATE household_cards SET status=?,assignee=?,doneAt=?,revision=revision+1 WHERE familyId=? AND id=? AND revision=?');
  const edit = db.prepare('UPDATE household_cards SET title=?,detail=?,list=?,deadline=?,checklist=?,revision=revision+1 WHERE familyId=? AND id=? AND revision=?');
  const updateChecklist = db.prepare('UPDATE household_cards SET checklist=?,revision=revision+1 WHERE familyId=? AND id=? AND revision=?');
  const remove = db.prepare("UPDATE household_cards SET deleted=1,images='[]',title='',detail='',list='',deadline=0,checklist='[]',revision=revision+1 WHERE familyId=? AND id=? AND revision=?");
  const attachment = db.prepare('SELECT id,mime,w,h,size FROM attachments WHERE id=? AND familyId=?');
  const clean = (value, max) => typeof value === 'string' && value.trim().length <= max ? value.trim() : null;
  const error = (status, message) => [status, { error: message }];
  const validDeadline = value => Number.isSafeInteger(value) && value >= 0 && value <= 8_640_000_000_000_000;
  function checklist(input, previous = []) {
    if (!Array.isArray(input) || input.length > 30) return null;
    const existing = new Map(previous.map(item => [item.id, item.checked]));
    const ids = new Set();
    const result = [];
    for (const item of input) {
      const title = clean(item?.title, 120);
      if (!isUuid(item?.id) || !title || ids.has(item.id)) return null;
      ids.add(item.id);
      result.push({ id: item.id, title, checked: existing.get(item.id) === true });
    }
    return result;
  }

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
        const deadline = item?.deadline ?? 0;
        const steps = checklist(item?.checklist ?? []);
        if (!isUuid(item?.id) || !title || detail === null || !Array.isArray(ids) || ids.length > 9 || !ids.every(isUuid)
          || !validDeadline(deadline) || steps === null) {
          return error(400, 'invalid card');
        }
        const images = [...new Set(ids)].map(id => attachment.get(id, familyId));
        if (images.some(image => !image)) return error(400, 'attachment not found in family');
        prepared.push({ id: item.id, title, detail, images, deadline, steps });
      }
      const now = Date.now();
      transaction(() => {
        for (const item of prepared) insert.run(item.id, familyId, name || '日常', item.title, item.detail,
          JSON.stringify(item.images), userId, now, item.deadline, JSON.stringify(item.steps));
      });
      return [200, { ok: true }];
    },
    act(id, body) {
      const { familyId, userId, action, revision } = body || {};
      if (!isUuid(id) || !isFamily(familyId) || !isRole(userId) || !Number.isInteger(revision)
        || !['claim', 'release', 'complete', 'edit', 'delete', 'reopen', 'check'].includes(action)) return error(400, 'invalid card action');
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
        const deadline = body.deadline === undefined ? card.deadline : body.deadline;
        const oldSteps = JSON.parse(card.checklist);
        const steps = body.checklist === undefined ? oldSteps : checklist(body.checklist, oldSteps);
        if (!title || detail === null || name === null || !validDeadline(deadline) || steps === null) return error(400, 'invalid card fields');
        edit.run(title, detail, name || '日常', deadline, JSON.stringify(steps), familyId, id, revision);
      } else if (action === 'check') {
        if (card.status === 'done') return error(409, 'card already completed');
        if (!isUuid(body.itemId) || typeof body.checked !== 'boolean') return error(400, 'invalid checklist item');
        const steps = JSON.parse(card.checklist);
        const item = steps.find(step => step.id === body.itemId);
        if (!item) return error(404, 'checklist item not found');
        if (item.checked !== body.checked) {
          item.checked = body.checked;
          updateChecklist.run(JSON.stringify(steps), familyId, id, revision);
        }
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
