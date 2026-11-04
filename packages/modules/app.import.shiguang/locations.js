// Location changes are explicit import options. Never overwrite captured data.
export const locationModes=[
  {value:'keep',label:'保留完整地点'},
  {value:'removeCampus',label:'去掉校区，保留教室'},
  {value:'omit',label:'不导入地点'},
];
export function locationSettings(options={}) {
  const locationMode=options.locationMode??'keep';
  if (!locationModes.some(mode=>mode.value===locationMode)) throw new Error('地点处理方式无效');
  const value=options.campusNames??'';
  if (typeof value!=='string' || value.length>2000) throw new Error('校区名称无效');
  const names=[...new Set(value.split(/\r?\n/).map(name=>name.trim()).filter(Boolean))];
  if (names.length>30 || names.some(name=>name.length>100)) throw new Error('最多填写30个校区名称，每个最多100字');
  if (locationMode==='removeCampus' && !names.length) throw new Error('请填写要去掉的校区名称，或选择不导入地点');
  return {locationMode,campusNames:names.join('\n')};
}
export function suggestedCampusNames(payload) {
  const rows=Array.isArray(payload)?payload:payload?.courses;
  if (!Array.isArray(rows)) return '';
  const names=new Set();
  for (const row of rows) {
    if (typeof row?.position!=='string') continue;
    const value=row.position.trim();
    // Suggest a bounded prefix or a clearly separated suffix. The user sees
    // and may edit these exact names before opting in to removal.
    const prefix=value.match(/^[（(【\[]?([^\s,，;；:：/\\|()（）\[\]【】]{1,40}?校区)/);
    const suffix=value.match(/(?:[（(【\[]|[\s,，;；/|])([^\s,，;；:：/\\|()（）\[\]【】]{1,40}?校区)[）)】\]]?$/);
    for (const name of [prefix?.[1],suffix?.[1]]) {
      // A room code before a trailing campus label is ambiguous. Leave it for
      // explicit user input rather than suggesting removal of the whole room.
      if (name && !/[0-9楼室馆]/.test(name) && names.size<30) names.add(name);
    }
    if (names.size>=30) break;
  }
  return [...names].join('\n');
}
export function importLocation(location,settings) {
  if (settings.locationMode==='omit') return '';
  if (settings.locationMode!=='removeCampus') return location;
  let result=location.trim();
  const wrappers=[['(',')'],['（','）'],['[',']'],['【','】']];
  // Longest first prevents a shorter campus name from partially stripping a
  // longer one. Exact text comparisons avoid regex interpretation of names.
  const names=settings.campusNames.split('\n').sort((a,b)=>b.length-a.length);
  for (const name of names) {
    for (const [open,close] of wrappers) {
      const wrapped=open+name+close;
      if (result.startsWith(wrapped)) result=result.slice(wrapped.length).replace(/^[\s,，;；:：/|·]+/,'');
      if (result.endsWith(wrapped)) result=result.slice(0,-wrapped.length).replace(/[\s,，;；:：/|·-]+$/,'');
    }
    if (result.startsWith(name)) result=result.slice(name.length).replace(/^[\s,，;；:：/|·]+/,'');
    if (result.endsWith(name)) {
      const before=result.slice(0,-name.length);
      if (!before || /[\s,，;；:：/|·-]$/.test(before)) result=before.replace(/[\s,，;；:：/|·-]+$/,'');
    }
  }
  return result;
}
export function locationSummary(options={}) {
  return locationModes.find(mode=>mode.value===(options.locationMode??'keep'))?.label||locationModes[0].label;
}
