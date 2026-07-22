export const unrestrictedReadRoles=["owner","system_administrator"] as const;
export function hasUnrestrictedRead(roles:string[]){return roles.some(role=>(unrestrictedReadRoles as readonly string[]).includes(role))}
