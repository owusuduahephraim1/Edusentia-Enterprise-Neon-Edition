(()=>{
  "use strict";
  if(window.EDS_INSTITUTION_ACADEMICS_LOADER_V1)return;
  window.EDS_INSTITUTION_ACADEMICS_LOADER_V1=true;
  // Neon uses the certified academic configuration RPC surface for both launch models.
  // The legacy direct-table browser client is intentionally retired.
  window.EdusentiaInstitutionAcademics=Object.freeze({
    mode:"certified-neon",
    supports:["basic_jhs","senior_high"],
    open(){window.EdusentiaShell?.navigate?.("academics");}
  });
})();