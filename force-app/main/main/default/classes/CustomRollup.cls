// B"H
// Test: CustomRollupTest

public without sharing class CustomRollup implements Queueable {
    public static Boolean isExecutionStarted = false;
    // added by Anatoly 21.05
    // in some cases CPQ jobs (QueueableCalculatorService) should be scheduled by system.
    // we can't add this job to queue. this flag should control this behaivor.
    public static Boolean isExecutionAllowed = true;
    
    
    private List<Sobject> triggerList;
    private Set<String> recordIdSet;
    private static String lastJobId; 
    
    final Map<String, Boolean> contextMap;
    final String obj;
    private List<Custom_Rollup_Configuration__mdt> rollups;
    Type t;
    
    private Map<String, Boolean> contextMapForTest = new Map<String, Boolean>{'Before_Insert__c' => true, 'Before_Update__c' => false, 'After_Insert__c' => false,
        'After_Update__c' => false, 'Before_Delete__c' => false, 'After_Undelete__c' => false};
            private String objForTest = String.valueOf(Case.getSobjectType());
    private static List<Case> newListForTest = new List<Case>();
    
    String currentObj;
    Map<Id, sObject> mapToUpdate;
    String rollupNames;
    
    private static CustomRollup instance;
    
    private CustomRollup(){
        System.debug('CustomRollup.constructor ');
        if (!Test.isRunningTest()) {
            contextMap 		= new Map<String, Boolean>{	
                'Before_Insert__c' 	=> (Trigger.isBefore && Trigger.isInsert),
                    'Before_Update__c' 	=> (Trigger.isBefore && Trigger.isUpdate),
                    'After_Insert__c' 	=> (Trigger.isAfter && Trigger.isInsert),
                    'After_Update__c' 	=> (Trigger.isAfter && Trigger.isUpdate),
                    'Before_Delete__c' 	=> (Trigger.isBefore && Trigger.isDelete),
                    'After_Undelete__c' => (Trigger.isAfter && Trigger.isUndelete)
                    };
                        obj 			= getSobjectType();
        } else {
            contextMap = contextMapForTest;
            obj = objForTest;
            if(CheckRecursive.executed('CustomRollupTestRecords')){
                Account acc = new Account(Name = 'test account');
                insert acc;
                Case c = new Case(AccountId = acc.Id);
                insert c; 
                
                newListForTest.addAll(new List<Case>{c});
                System.debug('cases' + c);
            }
            
        }
        
        mapToUpdate 	= new Map<Id, sObject>();
        rollupNames 	= '';
    }
    // udpates by Anatoly 08.04.2019
    // moved to singleton (avoid limits)
    // aborted and enqueue for keeping only 1 execution per context. 
    
    public static CustomRollup initAndCheckRollup(){
        Boolean hasUpdates = false;
        if (instance == null){
            instance = new CustomRollup();
        }
        if (instance.triggerList == null){
            instance.triggerList = new List <Sobject>();
            System.debug('in new list');
        }
        if (instance.recordIdSet == null){
            instance.recordIdSet = new Set<String> ();
        }
        if (instance.rollups == null){
            instance.rollups = new List <Custom_Rollup_Configuration__mdt> ();
        }
        instance.rollups.addAll(instance.getMetadata());
        
        if (!isExecutionAllowed){
            return instance;
        }
        
        for (Sobject obj_i : (!Test.isRunningTest() ? (!Trigger.isDelete ? Trigger.new : Trigger.old) : newListForTest)){
            if (!instance.recordIdSet.contains((String)obj_i.get('Id'))){
                instance.recordIdSet.add((String)obj_i.get('Id'));
                instance.triggerList.add(obj_i);
                hasUpdates = true;
            }
        }
        
        System.debug('instance.triggerList' + instance.triggerList);
        System.debug('instance.triggerList.size '+instance.triggerList.size());
        System.debug('instance.recordIdSet.size '+instance.recordIdSet.size());
        if(hasUpdates){
            if (String.isNotBlank(lastJobId)){
                System.abortJob(lastJobId);
            }
            System.debug('lastJobId '+lastJobId);
            lastJobId = System.enqueueJob(instance);
        }
        
        return instance;
        
    }
    
    public void execute(QueueableContext context){
        // added by Anatoly
        isExecutionStarted = true;
        System.debug('in execute isExecutionStarted '+isExecutionStarted);
        try{
            buildRollupQueries();
        }catch(Exception e){
            EmailUtils.exceptionToMis('CustomRollup.execute', e);
        }finally{
            EmailUtils.sendAndClear();
        }
    }
    
    public String getSobjectType(){
        sObject obj = (!Trigger.isDelete ? Trigger.new[0] : Trigger.old[0]);
        return obj.getSObjectType().getDescribe().getName();
    }
    /*
public String buildQuery(){
String query ='WHERE Child_Object__c = ' + obj + ' AND ';
for(String context : contextMap.keySet()){
if(contextMap.get(context)){
query += context + '= true AND ';
}
}
query = query.removeEndIgnoreCase('AND ');
return '';
}
*/
    public List<Custom_Rollup_Configuration__mdt> getMetadata(){
        Map<String, Schema.SObjectField> fieldMap = Schema.getGlobalDescribe().get('Custom_Rollup_Configuration__mdt').getDescribe().Fields.getMap();
        Map<String, String> testList = new Map<String, String>{'One' => 'One','Two' => 'Two'};
            
            String query = 'SELECT ';
        query += addFieldsToQuery(fieldMap.keySet());
        query += ' FROM Custom_Rollup_Configuration__mdt ';
        query += 'WHERE Child_Object__c = \'' + obj + '\' AND Active__c = true AND ';
        
        /* commented by Anatoly 11.04.2019
* not sure if we need this ooption 
for(String context : contextMap.keySet()){
if(contextMap.get(context)){
query += context + '= true AND ';
}
}
*/
        query = query.removeEndIgnoreCase('AND ');
        query += ' ORDER BY Parent_Object__c';
        System.debug('>>> ' + query);
        
        return Database.query(query);
    }
    
    public String addFieldsToQuery(Set<String> fields){
        String query = '';
        for (String field_i : fields) {
            query += field_i + ',';
        }
        query = query.removeEnd(',');
        return query;
    }
    
    public void buildRollupQueries(){
        System.debug('in processing triggerList.size '+triggerList.size());
        System.debug('rollups '+rollups);
        // Loop all Custom Rollup for current child object and context
        for(Custom_Rollup_Configuration__mdt rollup_i : rollups){
            System.debug('rollup_i '+rollup_i);
            // Set currentObj if null, and update list and then clear it if switching to the next parent object type and the list is not null.
            // Since Rollups are sorted by parent object, we can do multiple manipulations with a single update per object.
            if(currentObj == null){
                currentObj = rollup_i.Parent_Object__c;
            } else if(currentObj != rollup_i.Parent_Object__c){
                updateRecords();
                
                currentObj = rollup_i.Parent_Object__c;
            }
            rollupNames += rollup_i.Label;
            System.debug('rollupNames '+rollupNames);
            // Set Type for later record instantioation.
            t = Type.forName(currentObj);
            
            // Get list of parent ids to run the update on
            system.debug('LOOG '+triggerList+' '+rollup_i.Lookup_API_Name__c);
            Map<String, String> lookupIds = getListByApiName(triggerList, rollup_i.Lookup_API_Name__c);
            List<String> tempLookupIds = new List<String>(lookupIds.keySet());
            System.debug('tempLookupIds '+tempLookupIds);
            String query = buildQueryFromRollupConfig(rollup_i);
            System.debug('query '+query);
            List<Sobject> queriedRecords = Database.query(query);
            System.debug('queriedRecords.size '+queriedRecords.size());
            for(Sobject record_i : queriedRecords){
                String recId 		= (String)record_i.get(rollup_i.Lookup_API_Name__c);
                String targetField 	= rollup_i.Parent_Target_Field__c;
                Object fieldValue	= record_i.get(rollup_i.Operation__c+'1');
                // added by Anatoly 11.04.2019 
                // null for count and sum, not sure if we need it
                if ((rollup_i.Operation__c == 'COUNT' || rollup_i.Operation__c == 'SUM') && fieldValue == null){
                    fieldValue = 0;					
                }
                
                setupRecordWithRollup(recId, targetField, fieldValue);
                lookupIds.remove(recId);
            }
            if(!lookupIds.isEmpty()){
                for(String recId_i: lookupIds.values()){
                    String targetField 	= rollup_i.Parent_Target_Field__c;
                    Object fieldValue	= null;
                    
                    setupRecordWithRollup(recId_i, targetField, fieldValue);
                    lookupIds.remove(recId_i);
                }
            }
        }
        updateRecords();
    }
    
    public void updateRecords(){
        System.debug('mapToUpdate '+mapToUpdate);
        if(!mapToUpdate.isEmpty()){
            Database.SaveResult[] srList = Database.update(mapToUpdate.values(), false);
            String Body = 'CustomRollup Error: ' + rollupNames + ', ' + contextMap + '<br/>';
            Boolean hasErrors = false;
            for(Integer i=0;i<srList.size();i++){
                Database.SaveResult result = srList.get(i);
                if (!result.isSuccess()){
                    hasErrors = true;
                    for (Database.Error err : result.getErrors()){
                        body += '<br/>ID: ' + mapToUpdate.values().get(i).Id + ' Error: '+ err.getStatusCode() + ' ' + err.getMessage();
                        System.debug('Error: '+ err.getStatusCode() + ' ' + err.getMessage());
                    }
                }
            }
            System.debug('hasErrors '+hasErrors);
            if(hasErrors){
                EmailUtils.emailToMis('CustomRollup Error', body);
            }
            mapToUpdate.clear();       
        }
        rollupNames = '';
    }
    
    public String buildQueryFromRollupConfig(Custom_Rollup_Configuration__mdt rollup_i){
        String query = 'SELECT ' + rollup_i.Lookup_API_Name__c + ', ' + rollup_i.Operation__c + '(' + rollup_i.Child_Source_Field__c + ')' + rollup_i.Operation__c + '1 FROM ';
        query += rollup_i.Child_Object__c + ' WHERE ' + rollup_i.Lookup_API_Name__c + ' IN : tempLookupIds ';
        query +=  (rollup_i.Filter__c != null ? ' AND ' + rollup_i.Filter__c : '');
        query += ' GROUP BY ' + rollup_i.Lookup_API_Name__c;
        return query;
    }
    
    public sObject setupRecordWithRollup(String id, String field, Object value){
        sObject newObj = getsObject(id);
        
        if(value instanceof String){
            newObj.put(field, (String)value);
        }else if(value instanceof Date){
            newObj.put(field, (Date)value);
        }else if(value instanceof Datetime){
            newObj.put(field, (Datetime)value);
        }else if(value instanceof Time){
            newObj.put(field, (Time)value);
        }else if(value instanceof Integer){
            newObj.put(field, (Integer)value);
        }else if(value instanceof Decimal){
            newObj.put(field, (Decimal)value);
        }else{
            newObj.put(field, value);
        }
        return newObj;
    }
    
    public sObject getsObject(String id){
        sObject newObj;
        if(!mapToUpdate.containsKey(Id)){
            newObj = (sObject)t.newInstance();
            newObj.Id = id;
            mapToUpdate.put(Id, newObj);
        }else{
            newObj = mapToUpdate.get(id);
        }
        return newObj;
    }
    
    public Map<String, String> getListByApiName(List<sObject> objList, String fieldApi){
        Map<String, String> lookupIds = new Map<String, String>();
        for(sObject obj_i : objList){
            String lookupId = (String) obj_i.get(fieldApi);
            if(lookupId != null){
                lookupIds.put(lookupId, lookupId);
            }
        }
        return lookupIds;
    }
    
    
    
    
    
}