# Schema Migration Complete ✅

## Summary
The database schema and Flutter code have been successfully updated to support the new normalized structure and 3-stage approval workflow.

## Database Changes Completed

### 1. Approval Status Enum
**Updated from 6 values to 3 values:**
- ✅ `submitted` - User submits time period (Stage 1)
- ✅ `supervisor_approved` - Supervisor/Manager approves (Stage 2)
- ✅ `admin_approved` - Admin final approval (Stage 3)

**Removed:** `draft`, `approved`, `rejected`

### 2. New Normalized Tables Created
- ✅ `time_period_breaks` - One row per break (replaces break columns in time_periods)
- ✅ `time_period_used_fleet` - One row per used fleet item (replaces time_used_large_plant)
- ✅ `time_period_mobilised_fleet` - One row per mobilised fleet item (replaces time_mobilised_large_plant)
- ✅ `time_period_pay_rates` - One row per pay rate type (new functionality)
- ✅ `time_period_revisions` - Audit trail for changes (already existed, enhanced)

### 3. RLS Policies Applied
- ✅ Users can view/edit their own `submitted` time periods
- ✅ Supervisors can view/edit `submitted` time periods and change status to `supervisor_approved`
- ✅ Admins can view/edit all time periods and change status to `admin_approved`
- ✅ Revisions are read-only (immutable audit trail)

## Flutter Code Changes Completed

### File: `lib/screens/timesheet_screen.dart`

#### 1. Status Value Updated (Line ~3552)
```dart
// OLD: 'status': 'draft'
// NEW: 'status': 'submitted'
```

#### 2. Break Saving Updated (Line ~3654-3668)
- ✅ Changed table name from `time_breaks` to `time_period_breaks`
- ✅ Added `break_duration_min` calculation
- ✅ Each break saved as separate row

#### 3. Used Fleet Saving Updated (Line ~4826-4903)
- ✅ Changed from numbered columns to separate rows
- ✅ Changed table name to `time_period_used_fleet`
- ✅ One row per fleet item with `large_plant_id` and `plant_number`

#### 4. Mobilised Fleet Saving Updated (Line ~4905-4960)
- ✅ Changed from numbered columns to separate rows
- ✅ Changed table name to `time_period_mobilised_fleet`
- ✅ One row per fleet item with `large_plant_id` and `plant_number`

## Files Created During Migration

1. **`SCHEMA_WITH_APPROVAL_WORKFLOW.md`** - Initial schema design with workflow
2. **`SCHEMA_WITH_PAY_RATES.md`** - Enhanced schema with pay rate tables
3. **`COMPLETE_SCHEMA_SUMMARY.md`** - Overview of complete schema
4. **`TIME_VALIDATION_RULES.md`** - 15-minute increment validation rules
5. **`IMPLEMENTATION_GUIDE.md`** - Step-by-step implementation guide
6. **`CREATE_COMPLETE_SCHEMA.sql`** - Database creation script (executed ✅)
7. **`UPDATE_APPROVAL_STATUS_ENUM.sql`** - Initial enum update (superseded)
8. **`RECREATE_APPROVAL_STATUS_ENUM.sql`** - Final enum recreation (executed ✅)
9. **`CREATE_RLS_POLICIES.sql`** - RLS policies (executed ✅)
10. **`FLUTTER_MIGRATION_GUIDE.md`** - Flutter code migration guide
11. **`SCHEMA_MIGRATION_COMPLETE.md`** - This summary document

## Testing Checklist

### Database Tests
- [ ] Verify enum has only 3 values: `submitted`, `supervisor_approved`, `admin_approved`
- [ ] Confirm all 6 new tables exist
- [ ] Check RLS policies are enabled on all tables
- [ ] Test user can create time periods with status='submitted'
- [ ] Test user cannot change status beyond 'submitted'
- [ ] Test supervisor can change status from 'submitted' to 'supervisor_approved'
- [ ] Test admin can change status from 'supervisor_approved' to 'admin_approved'

### Flutter App Tests
- [ ] Create a new time period
- [ ] Add breaks (verify saved to `time_period_breaks`)
- [ ] Add used fleet (verify saved to `time_period_used_fleet` as separate rows)
- [ ] Add mobilised fleet (verify saved to `time_period_mobilised_fleet` as separate rows)
- [ ] Verify status is set to 'submitted'
- [ ] Check all data saves correctly
- [ ] Test offline mode (if applicable)
- [ ] Test reading data back
- [ ] Test that users can only edit their own 'submitted' entries

### Query Tests (Run in Supabase SQL Editor)

#### 1. Check Time Period with Related Data
```sql
-- Get time period with all related data
SELECT 
  tp.id,
  tp.user_id,
  tp.status,
  tp.work_date,
  tp.start_time,
  tp.finish_time,
  -- Count related records
  (SELECT COUNT(*) FROM time_period_breaks WHERE time_period_id = tp.id) as break_count,
  (SELECT COUNT(*) FROM time_period_used_fleet WHERE time_period_id = tp.id) as used_fleet_count,
  (SELECT COUNT(*) FROM time_period_mobilised_fleet WHERE time_period_id = tp.id) as mobilised_fleet_count
FROM time_periods tp
ORDER BY tp.created_at DESC
LIMIT 10;
```

#### 2. View Breaks for a Time Period
```sql
SELECT 
  b.*,
  tp.work_date,
  tp.status
FROM time_period_breaks b
JOIN time_periods tp ON tp.id = b.time_period_id
ORDER BY b.created_at DESC
LIMIT 10;
```

#### 3. View Fleet Items
```sql
-- Used Fleet
SELECT 
  uf.*,
  lp.plant_no,
  lp.description,
  tp.work_date,
  tp.status
FROM time_period_used_fleet uf
JOIN time_periods tp ON tp.id = uf.time_period_id
LEFT JOIN large_plant lp ON lp.id = uf.large_plant_id
ORDER BY uf.created_at DESC
LIMIT 10;

-- Mobilised Fleet
SELECT 
  mf.*,
  lp.plant_no,
  lp.description,
  tp.work_date,
  tp.status
FROM time_period_mobilised_fleet mf
JOIN time_periods tp ON tp.id = mf.time_period_id
LEFT JOIN large_plant lp ON lp.id = mf.large_plant_id
ORDER BY mf.created_at DESC
LIMIT 10;
```

## Next Steps

### Immediate
1. **Test the updated code** thoroughly
2. **Verify RLS policies** work as expected
3. **Check offline sync** (if applicable)

### Future Enhancements
1. **Pay Rate Allocation UI** - Add UI for splitting hours into pay rate categories
2. **15-Minute Validation** - Add time picker validation for 15-minute increments
3. **Revision Tracking UI** - Show users what was changed by supervisors/admins
4. **Approval Workflow UI** - Build supervisor and admin approval screens
5. **System Settings UI** - Allow admins to configure break/fleet limits

## Configuration

### System Settings (Configurable Limits)
These can be updated in the `system_settings` table:

```sql
UPDATE system_settings 
SET 
  max_breaks_per_period = 3,           -- Default: 3 breaks
  max_used_fleet_per_period = 6,       -- Default: 6 used fleet items
  max_mobilised_fleet_per_period = 4   -- Default: 4 mobilised fleet items
WHERE id = (SELECT id FROM system_settings LIMIT 1);
```

## Rollback Plan

If you need to rollback (NOT recommended after data exists):

1. **DO NOT** run rollback if you have real data in the new tables
2. Export all data from new tables first
3. Recreate old schema
4. Migrate data back (requires custom migration script)

## Support

### Troubleshooting Common Issues

**Issue**: "Permission denied" when creating time periods  
**Solution**: Check RLS policies, ensure user is authenticated

**Issue**: Fleet items not saving  
**Solution**: Verify `large_plant` table has correct data and RLS allows reading

**Issue**: Cannot change status  
**Solution**: Only supervisors can change 'submitted' → 'supervisor_approved', only admins can change to 'admin_approved'

**Issue**: Breaks not appearing  
**Solution**: Check `time_period_breaks` table directly, verify time_period_id matches

## Documentation References

- **Schema Design**: `SCHEMA_WITH_PAY_RATES.md`
- **RLS Policies**: `CREATE_RLS_POLICIES.sql`
- **Flutter Guide**: `FLUTTER_MIGRATION_GUIDE.md`
- **Time Validation**: `TIME_VALIDATION_RULES.md`
- **Implementation**: `IMPLEMENTATION_GUIDE.md`

## Success Criteria

✅ Database schema created  
✅ RLS policies applied  
✅ Flutter code updated  
⏳ Testing in progress  
⏳ Approval workflow UI (future)  
⏳ Pay rate allocation (future)  

---

**Migration completed on**: December 16, 2025  
**Database**: Supabase PostgreSQL  
**App Framework**: Flutter  
**Status**: Code updated, ready for testing

