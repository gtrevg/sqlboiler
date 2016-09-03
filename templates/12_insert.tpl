{{- $tableNameSingular := .Table.Name | singular | titleCase -}}
{{- $varNameSingular := .Table.Name | singular | camelCase -}}
// InsertG a single record. See Insert for whitelist behavior description.
func (o *{{$tableNameSingular}}) InsertG(whitelist ... string) error {
  return o.Insert(boil.GetDB(), whitelist...)
}

// InsertGP a single record, and panics on error. See Insert for whitelist
// behavior description.
func (o *{{$tableNameSingular}}) InsertGP(whitelist ... string) {
  if err := o.Insert(boil.GetDB(), whitelist...); err != nil {
    panic(boil.WrapErr(err))
  }
}

// InsertP a single record using an executor, and panics on error. See Insert
// for whitelist behavior description.
func (o *{{$tableNameSingular}}) InsertP(exec boil.Executor, whitelist ... string) {
  if err := o.Insert(exec, whitelist...); err != nil {
    panic(boil.WrapErr(err))
  }
}

// Insert a single record using an executor.
// Whitelist behavior: If a whitelist is provided, only those columns supplied are inserted
// No whitelist behavior: Without a whitelist, columns are inferred by the following rules:
// - All columns without a default value are included (i.e. name, age)
// - All columns with a default, but non-zero are included (i.e. health = 75)
func (o *{{$tableNameSingular}}) Insert(exec boil.Executor, whitelist ... string) error {
  if o == nil {
    return errors.New("{{.PkgName}}: no {{.Table.Name}} provided for insertion")
  }

  var err error
  {{- template "timestamp_insert_helper" . }}

  {{if not .NoHooks -}}
  if err := o.doBeforeInsertHooks(exec); err != nil {
    return err
  }
  {{- end}}

  nzDefaults := boil.NonZeroDefaultSet({{$varNameSingular}}ColumnsWithDefault, o)

  key := makeCacheKey(whitelist, nzDefaults)
  {{$varNameSingular}}InsertCacheMut.RLock()
  cache, cached := {{$varNameSingular}}InsertCache[key]
  {{$varNameSingular}}InsertCacheMut.RUnlock()

  if !cached {
    wl, returnColumns := strmangle.InsertColumnSet(
      {{$varNameSingular}}Columns,
      {{$varNameSingular}}ColumnsWithDefault,
      {{$varNameSingular}}ColumnsWithoutDefault,
      nzDefaults,
      whitelist,
    )

    cache.valueMapping, err = boil.BindMapping({{$varNameSingular}}Type, {{$varNameSingular}}Mapping, wl)
    if err != nil {
      return err
    }
    cache.retMapping, err = boil.BindMapping({{$varNameSingular}}Type, {{$varNameSingular}}Mapping, returnColumns)
    if err != nil {
      return err
    }
    cache.query = fmt.Sprintf(`INSERT INTO {{.Table.Name}} ("%s") VALUES (%s)`, strings.Join(wl, `","`), strmangle.Placeholders(len(wl), 1, 1))

    if len(cache.retMapping) != 0 {
      {{if .UseLastInsertID -}}
      cache.retQuery = fmt.Sprintf(`SELECT %s FROM {{.Table.Name}} WHERE %s`, strings.Join(returnColumns, `","`), strmangle.WhereClause(1, {{$varNameSingular}}PrimaryKeyColumns))
      {{else -}}
      cache.query += fmt.Sprintf(` RETURNING %s`, strings.Join(returnColumns, ","))
      {{end -}}
    }
  }

  value := reflect.Indirect(reflect.ValueOf(o))
  vals := boil.ValuesFromMapping(value, cache.valueMapping)
  {{if .UseLastInsertID}}
  if boil.DebugMode {
    fmt.Fprintln(boil.DebugWriter, cache.query)
    fmt.Fprintln(boil.DebugWriter, vals)
  }

  result, err := exec.Exec(ins, vals...)
  if err != nil {
    return errors.Wrap(err, "{{.PkgName}}: unable to insert into {{.Table.Name}}")
  }

  if len(cache.retMapping) == 0 {
  {{if not .NoHooks -}}
    return o.doAfterInsertHooks(exec)
  {{else -}}
    return nil
  {{end -}}
  }

  lastID, err := result.LastInsertId()
  if err != nil || lastID == 0 || len({{$varNameSingular}}PrimaryKeyColumns) != 1 {
    return ErrSyncFail
  }

  if boil.DebugMode {
    fmt.Fprintln(boil.DebugWriter, cache.retQuery)
    fmt.Fprintln(boil.DebugWriter, lastID)
  }

  err = exec.QueryRow(cache.retQuery, lastID).Scan(boil.PtrsFromMapping(value, cache.retMapping)...)
  if err != nil {
    return errors.Wrap(err, "{{.PkgName}}: unable to populate default values for {{.Table.Name}}")
  }
  {{else}}
  if len(cache.retMapping) != 0 {
    err = exec.QueryRow(cache.query, vals...).Scan(boil.PtrsFromMapping(value, cache.retMapping)...)
  } else {
    _, err = exec.Exec(cache.query, vals...)
  }

  if boil.DebugMode {
    fmt.Fprintln(boil.DebugWriter, cache.query)
    fmt.Fprintln(boil.DebugWriter, vals)
  }

  if err != nil {
    return errors.Wrap(err, "{{.PkgName}}: unable to insert into {{.Table.Name}}")
  }
  {{end}}

  {{$varNameSingular}}InsertCacheMut.Lock()
  {{$varNameSingular}}InsertCache[key] = cache
  {{$varNameSingular}}InsertCacheMut.Unlock()

  {{if not .NoHooks -}}
  return o.doAfterInsertHooks(exec)
  {{- else -}}
  return nil
  {{- end}}
}
