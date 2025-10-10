import express from "express";
import {
  addLead,
  getAllLeads,
  getLeadById,
  deleteLead,
  convertLeadToClient,
} from "../Controller/leadController.js";   
import { authenticate } from "../Middleware/authentication.js";

const router = express.Router();

router.post("/addlead", authenticate,addLead);
router.get("/getlead",authenticate,getAllLeads);
router.get("/:id",authenticate,getLeadById);
router.delete("/:id",authenticate, deleteLead);

router.post("/convert/:leadId",  convertLeadToClient);

export default router;
