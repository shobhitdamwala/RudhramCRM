import express from "express";
import { createSubCompany, getAllSubCompanies, getSubCompanyById } from "../Controller/subCompanyController.js";

const router = express.Router();


router.post('/addsubcompany',createSubCompany);
router.get("/getsubcompany", getAllSubCompanies);
router.get("/getsubcompany/:id", getSubCompanyById);

export default router;